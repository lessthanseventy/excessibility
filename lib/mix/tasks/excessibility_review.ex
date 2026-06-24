defmodule Mix.Tasks.Excessibility.Review do
  @shortdoc "Report the accessibility blast radius of changes vs the baseline"

  @moduledoc """
  Reports what the current snapshots changed relative to the baseline.

  For every snapshot with a baseline, this diffs the rendered output and
  reports, per view, the regions that changed and the accessibility issues
  the change **newly introduced**, with a risk tier:

    * `block`  — a new critical/serious issue (e.g. a keyboard-inaccessible
      control introduced by this change)
    * `review` — a new moderate/minor issue, or content that changed
      without an `aria-live` announcement; worth a human glance
    * `auto`   — rendering changed but introduced no accessibility issues

  ## Usage

      # Generate/refresh snapshots, then review against the baseline
      mix test
      mix excessibility.review

      # Fail the build only on :block (default), on :review, or never
      mix excessibility.review --fail-on review
      mix excessibility.review --fail-on never

  Establish the baseline with `mix excessibility.baseline`.
  """

  use Mix.Task

  alias Excessibility.Review
  alias Excessibility.Review.Judge

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [fail_on: :string, judge: :boolean])
    fail_on = parse_fail_on(opts[:fail_on])

    report = Review.review()
    report = if Keyword.get(opts, :judge, false), do: judge_report(report), else: report

    if report.changes == [] do
      Mix.shell().info("No changes vs baseline.")
    else
      print_report(report)
    end

    maybe_exit(report.summary, fail_on)
  end

  # Run the configured judge over each change, overriding the heuristic tier
  # with the judge's verdict and recomputing the summary.
  defp judge_report(%{changes: changes}) do
    judged =
      Enum.map(changes, fn change ->
        verdict = Judge.verdict(change)
        change |> Map.put(:verdict, verdict) |> Map.put(:tier, verdict.tier)
      end)

    counts = Enum.frequencies_by(judged, & &1.tier)

    summary = %{
      auto: Map.get(counts, :auto, 0),
      review: Map.get(counts, :review, 0),
      block: Map.get(counts, :block, 0)
    }

    %{changes: judged, summary: summary}
  end

  defp parse_fail_on(nil), do: :block
  defp parse_fail_on("block"), do: :block
  defp parse_fail_on("review"), do: :review
  defp parse_fail_on("never"), do: :never

  defp parse_fail_on(other), do: Mix.raise("Unknown --fail-on value #{inspect(other)}. Use block, review, or never.")

  defp print_report(%{changes: changes, summary: summary}) do
    Mix.shell().info("## Blast radius vs baseline\n")

    changes
    |> Enum.sort_by(&tier_rank(&1.tier))
    |> Enum.each(&print_change/1)

    Mix.shell().info(
      "#{length(changes)} view(s) changed — " <>
        "#{summary.block} block, #{summary.review} review, #{summary.auto} auto"
    )
  end

  defp print_change(change) do
    label = change.tier |> Atom.to_string() |> String.upcase()
    Mix.shell().info("[#{label}] #{change.view} — #{change.region_count} region(s) changed")

    case Map.get(change, :verdict) do
      nil -> print_findings(change.findings)
      verdict -> print_verdict(verdict)
    end

    Mix.shell().info("")
  end

  defp print_findings(findings) do
    Enum.each(findings, fn finding ->
      Mix.shell().info("    #{finding.rule} @ #{finding.selector}")
      Mix.shell().info("      #{finding.message}")
    end)
  end

  defp print_verdict(verdict) do
    Mix.shell().info("    #{verdict.blast_radius}")

    Enum.each(verdict.risks, fn risk ->
      Mix.shell().info("    - [#{risk.severity}] #{risk.area}: #{risk.detail}")
    end)
  end

  defp tier_rank(:block), do: 0
  defp tier_rank(:review), do: 1
  defp tier_rank(:auto), do: 2

  defp maybe_exit(summary, :block) when summary.block > 0, do: exit({:shutdown, 1})
  defp maybe_exit(summary, :review) when summary.block + summary.review > 0, do: exit({:shutdown, 1})
  defp maybe_exit(_summary, _fail_on), do: :ok
end
