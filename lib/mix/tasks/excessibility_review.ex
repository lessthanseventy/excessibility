defmodule Mix.Tasks.Excessibility.Review do
  @shortdoc "Report the accessibility blast radius of changes vs the baseline"

  @moduledoc """
  Reports what the current snapshots changed relative to the baseline.

  For every snapshot with a baseline, this diffs the rendered output and
  reports, per view, the regions that changed and the accessibility issues
  the change **newly introduced**, with a risk tier:

    * `block`  — a new critical/serious issue (e.g. a keyboard-inaccessible
      control introduced by this change)
    * `review` — a new moderate/minor issue; worth a human glance
    * `auto`   — rendering changed but introduced no accessibility issues

  ## Usage

      # Generate/refresh snapshots, then review against the baseline
      mix test
      mix excessibility.review

      # Fail the build only on :block (default), on :review, or never
      mix excessibility.review --fail-on review
      mix excessibility.review --fail-on never

      # Emit one machine-readable JSON object on stdout instead of the human
      # report (for CI/PR bots — see the schema below). --json is an alias.
      mix excessibility.review --format json

      # Also fail the build on a serious *behavioral* finding. Off by default:
      # behavioral findings have no baseline (they're absolute measurements of
      # a single run), so they're advisory unless you opt in.
      mix excessibility.review --timeline test/excessibility/timeline.json --fail-on-behavioral

      # Fold in behavioral findings from a telemetry timeline (N+1 queries,
      # dead state, render thrash) captured by `mix excessibility.debug`
      mix excessibility.review --timeline test/excessibility/timeline.json --judge

      # Skip the axe-core browser scans and review on the LiveView rules only
      mix excessibility.review --no-axe

      # Also flag content that changed without an aria-live announcement.
      # Only turn this on when both sides rendered the SAME fixture data:
      # baseline and current usually come from two independent `mix test`
      # runs, and with non-deterministic fixtures the text delta reports
      # fixture drift, not accessibility regressions.
      mix excessibility.review --content-diff

  New findings are the union of axe-core violations (scanned per snapshot
  pair through Playwright) and the LiveView rules. If the axe scan fails
  (e.g. Playwright isn't installed), the review degrades to the LiveView
  rules and prints a warning.

  Establish the baseline with `mix excessibility.baseline`.
  """

  use Mix.Task

  alias Excessibility.Review

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [
          fail_on: :string,
          fail_on_behavioral: :boolean,
          judge: :boolean,
          timeline: :string,
          axe: :boolean,
          content_diff: :boolean,
          format: :string,
          json: :boolean
        ]
      )

    fail_on = parse_fail_on(opts[:fail_on])
    fail_on_behavioral? = Keyword.get(opts, :fail_on_behavioral, false)
    json? = json_output?(opts)

    stale_warning = stale_warning()

    report = Review.review(review_opts(opts))
    report = if Keyword.get(opts, :judge, false), do: Review.judge_changes(report), else: report

    if json? do
      report |> with_run_warnings(stale_warning) |> print_json()
    else
      if stale_warning, do: Mix.shell().info(stale_warning <> "\n")
      print_report(report)
    end

    maybe_exit(report, fail_on, fail_on_behavioral?)
  end

  defp json_output?(opts) do
    Keyword.get(opts, :json, false) or opts[:format] == "json"
  end

  # Load a telemetry timeline (mix excessibility.debug writes timeline.json) so
  # behavioral findings — N+1 queries, dead state, render thrash — inform the
  # review alongside the DOM diff.
  defp review_opts(opts) do
    base = [axe: Keyword.get(opts, :axe, true), content_diff: Keyword.get(opts, :content_diff, false)]

    case opts[:timeline] do
      nil -> base
      path -> [timeline: load_timeline!(path)] ++ base
    end
  end

  # keys: :atoms creates atoms from the file, which is fine for a dev tool
  # reading its own timeline.json (assign names are dynamic, so :atoms!
  # would raise); don't point this at untrusted input.
  defp load_timeline!(path) do
    with {:ok, raw} <- File.read(path),
         {:ok, timeline} <- Jason.decode(raw, keys: :atoms) do
      timeline
    else
      {:error, %Jason.DecodeError{}} ->
        Mix.raise("Could not parse timeline JSON at #{path}. Regenerate it with: mix excessibility.debug <test>")

      {:error, reason} ->
        Mix.raise("Could not read timeline at #{path}: #{inspect(reason)}")
    end
  end

  # A report generated from snapshots older than the baseline describes a
  # previous run, not the current change — say so instead of silently
  # reporting stale numbers. Returns the warning text (or nil) so both the
  # human report and the JSON output can surface it.
  defp stale_warning do
    with {:ok, newest_snapshot} <- newest_mtime("html_snapshots"),
         {:ok, newest_baseline} <- newest_mtime("baseline"),
         true <- newest_snapshot < newest_baseline do
      "WARNING: current snapshots predate the baseline — run `mix test` to refresh them before trusting this report."
    else
      _ -> nil
    end
  end

  # In JSON mode the stale-snapshot notice belongs in the report's warnings
  # array, not on stdout (which must carry only the JSON object). The
  # "WARNING: " prefix is stripped so the array holds prose, not log lines.
  defp with_run_warnings(report, nil), do: report

  defp with_run_warnings(report, stale_warning) do
    text = String.replace_prefix(stale_warning, "WARNING: ", "")
    Map.update(report, :warnings, [text], &[text | &1])
  end

  defp newest_mtime(subdir) do
    output_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

    mtimes =
      output_path
      |> Path.join(subdir)
      |> Path.join("*.html")
      |> Path.wildcard()
      |> Enum.map(&File.stat!(&1, time: :posix).mtime)

    case mtimes do
      [] -> :error
      list -> {:ok, Enum.max(list)}
    end
  end

  defp parse_fail_on(nil), do: :block
  defp parse_fail_on("block"), do: :block
  defp parse_fail_on("review"), do: :review
  defp parse_fail_on("never"), do: :never

  defp parse_fail_on(other), do: Mix.raise("Unknown --fail-on value #{inspect(other)}. Use block, review, or never.")

  defp print_report(%{changes: [], behavioral: []} = report) do
    print_warnings(Map.get(report, :warnings, []))
    Mix.shell().info("No changes vs baseline.")
  end

  defp print_report(%{changes: changes, summary: summary} = report) do
    print_warnings(Map.get(report, :warnings, []))
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

  defp print_warnings([]), do: :ok

  defp print_warnings(warnings) do
    Enum.each(warnings, &Mix.shell().info("WARNING: " <> &1))
    Mix.shell().info("")
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

  # Accessibility tiers gate the build via --fail-on (default :block).
  # Behavioral findings are advisory by default (they have no baseline, so
  # they're absolute single-run measurements, issue #142) and only gate the
  # build when the user opts in with --fail-on-behavioral.
  defp maybe_exit(report, fail_on, fail_on_behavioral?) do
    a11y_block? = report.summary.block > 0
    behavioral_block? = fail_on_behavioral? and behavioral_serious?(report)

    cond do
      behavioral_block? -> exit({:shutdown, 1})
      fail_on == :block and a11y_block? -> exit({:shutdown, 1})
      fail_on == :review and (a11y_block? or report.summary.review > 0) -> exit({:shutdown, 1})
      true -> :ok
    end
  end

  defp behavioral_serious?(report) do
    Enum.any?(Map.get(report, :behavioral, []), &(&1.severity == :serious))
  end

  # ── JSON output (issue #143) ───────────────────────────────────────
  #
  # One object on stdout so CI can consume the report without scraping the
  # human-readable text. Rule ids and severities are atoms internally, so
  # they're stringified on the way out; each finding carries a `source`
  # (`live_view_rules` / `axe` / `telemetry`) that the printed report only
  # implies.
  defp print_json(report) do
    report
    |> json_map()
    |> Jason.encode!(pretty: true)
    |> Mix.shell().info()
  end

  defp json_map(report) do
    %{
      excessibility_version: to_string(Application.spec(:excessibility, :vsn)),
      summary: report.summary,
      warnings: Map.get(report, :warnings, []),
      behavioral: Enum.map(Map.get(report, :behavioral, []), &json_behavioral/1),
      changes: Enum.map(report.changes, &json_change/1)
    }
  end

  defp json_behavioral(finding) do
    %{
      rule: to_string(finding.rule),
      severity: to_string(finding.severity),
      source: to_string(Map.get(finding, :source, :telemetry)),
      message: finding.message
    }
  end

  defp json_change(change) do
    %{
      view: change.view,
      tier: to_string(change.tier),
      region_count: change.region_count,
      findings: Enum.map(change.findings, &json_finding/1)
    }
  end

  defp json_finding(finding) do
    %{
      rule: to_string(finding.rule),
      severity: to_string(finding.severity),
      source: to_string(Map.get(finding, :source, :live_view_rules)),
      selector: Map.get(finding, :selector),
      message: finding.message
    }
  end
end
