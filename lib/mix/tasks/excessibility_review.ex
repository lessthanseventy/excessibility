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

      # Fold in behavioral findings from a telemetry timeline (N+1 queries,
      # dead state, render thrash) captured by `mix excessibility.debug`
      mix excessibility.review --timeline test/excessibility/timeline.json --judge

  Establish the baseline with `mix excessibility.baseline`.
  """

  use Mix.Task

  alias Excessibility.Review

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args, strict: [fail_on: :string, judge: :boolean, timeline: :string])

    fail_on = parse_fail_on(opts[:fail_on])

    report = Review.review(review_opts(opts))
    report = if Keyword.get(opts, :judge, false), do: Review.judge_changes(report), else: report

    print_report(report)
    maybe_exit(report, fail_on)
  end

  # Load a telemetry timeline (mix excessibility.debug writes timeline.json) so
  # behavioral findings — N+1 queries, dead state, render thrash — inform the
  # review alongside the DOM diff.
  defp review_opts(opts) do
    case opts[:timeline] do
      nil -> []
      path -> [timeline: path |> File.read!() |> Jason.decode!(keys: :atoms)]
    end
  end

  defp parse_fail_on(nil), do: :block
  defp parse_fail_on("block"), do: :block
  defp parse_fail_on("review"), do: :review
  defp parse_fail_on("never"), do: :never

  defp parse_fail_on(other), do: Mix.raise("Unknown --fail-on value #{inspect(other)}. Use block, review, or never.")

  defp print_report(%{changes: [], behavioral: []}) do
    Mix.shell().info("No changes vs baseline.")
  end

  defp print_report(%{changes: changes, summary: summary} = report) do
    Mix.shell().info("## Blast radius vs baseline\n")

    changes
    |> Enum.sort_by(&tier_rank(&1.tier))
    |> Enum.each(&print_change/1)

    print_behavioral(Map.get(report, :behavioral, []))

    Mix.shell().info(
      "#{length(changes)} view(s) changed — " <>
        "#{summary.block} block, #{summary.review} review, #{summary.auto} auto"
    )
  end

  defp print_behavioral([]), do: :ok

  defp print_behavioral(findings) do
    Mix.shell().info("### Behavioral (telemetry analyzers)\n")

    Enum.each(findings, fn finding ->
      Mix.shell().info("    [#{finding.severity}] #{finding.rule}: #{finding.message}")
    end)

    Mix.shell().info("")
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

    if judge_tier = Map.get(verdict, :judge_tier) do
      Mix.shell().info(
        "    (judge said #{judge_tier}; floored to #{verdict.tier} — " <>
          "a judge cannot fully green-light new serious findings)"
      )
    end
  end

  defp tier_rank(:block), do: 0
  defp tier_rank(:review), do: 1
  defp tier_rank(:auto), do: 2

  defp maybe_exit(report, fail_on) do
    block? = report.summary.block > 0 or behavioral_serious?(report)

    cond do
      fail_on == :block and block? -> exit({:shutdown, 1})
      fail_on == :review and (block? or report.summary.review > 0) -> exit({:shutdown, 1})
      true -> :ok
    end
  end

  # A critical analyzer finding (normalized to :serious) fails the run even
  # without --judge, the same as a serious accessibility regression.
  defp behavioral_serious?(report) do
    Enum.any?(Map.get(report, :behavioral, []), &(&1.severity == :serious))
  end
end
