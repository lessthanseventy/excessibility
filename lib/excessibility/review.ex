defmodule Excessibility.Review do
  @moduledoc """
  A blast-radius report for a snapshot run, measured against the baseline.

  Where `mix excessibility` checks each snapshot in isolation, a review
  asks a sharper question: *what did this change actually do?* It diffs
  every current snapshot against its baseline (the known-good/`main`
  state) and, per view, reports:

    * the rendered regions that changed (via `Excessibility.SnapshotDiff`)
    * the accessibility findings this change **newly introduced** —
      axe-core violations and `Excessibility.LiveViewRules` violations
      present now but not in the baseline (a finding-delta)
    * a risk **tier** — `:auto`, `:review`, or `:block`

  With `content_diff: true`, content that changed without an `aria-live`
  announcement is also flagged. That signal compares rendered text, so it
  is only meaningful when the baseline and current snapshots rendered the
  **same fixture data** — with the usual CI shape (baseline and current
  from two independent `mix test` runs) it mostly reports fixture drift,
  which is why it is off by default.

  axe-core runs through the configured `:scanner_mod` (a browser scan of
  each side of the pair); disable it with `axe: false`. When a scan fails
  (e.g. Playwright isn't installed) the review still runs on the LiveView
  rules alone and says so in the report's `:warnings`.

  The tier is a transparent heuristic over the new findings; a smarter
  judge can be layered on top of the same report. Because it diffs against
  the baseline rather than two git refs, it runs from an ordinary
  `mix test` + baseline, with no worktree gymnastics.
  """

  alias Excessibility.LiveViewRules
  alias Excessibility.Review.Behavioral
  alias Excessibility.Review.Judge
  alias Excessibility.SnapshotDiff

  @type tier :: :auto | :review | :block

  @type change :: %{
          view: String.t(),
          regions: [SnapshotDiff.region()],
          region_count: non_neg_integer(),
          findings: [map()],
          behavioral: [Behavioral.finding()],
          warnings: [String.t()],
          tier: tier()
        }

  @type report :: %{
          changes: [change()],
          behavioral: [Behavioral.finding()],
          warnings: [String.t()],
          summary: %{auto: non_neg_integer(), review: non_neg_integer(), block: non_neg_integer()}
        }

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Review every current snapshot that has a baseline, returning a report.

  Reads snapshots from the configured output path (`html_snapshots/` vs
  `baseline/`). Only views that actually changed (regions or findings)
  appear in `:changes`.
  """
  @spec review(keyword()) :: report()
  def review(opts \\ []) do
    # Behavioral findings come from the run's telemetry timeline, so they are
    # computed once at the report level rather than attached per view.
    timeline = Keyword.get(opts, :timeline)
    pair_opts = Keyword.delete(opts, :timeline)

    report =
      opts
      |> matched_pairs()
      |> review_pairs(pair_opts)

    behavioral = if timeline, do: Behavioral.findings(timeline, opts), else: []
    Map.put(report, :behavioral, behavioral)
  end

  @doc """
  Review a list of `{view, baseline_html, current_html}` tuples.

  Unchanged views (no regions and no findings) are dropped. Returns a
  report with per-view changes and a tier summary.
  """
  @spec review_pairs([{String.t(), String.t(), String.t()}], keyword()) :: report()
  def review_pairs(pairs, opts \\ []) do
    reviewed = Enum.map(pairs, fn {view, baseline, current} -> review_pair(view, baseline, current, opts) end)

    # Hoist warnings before dropping unchanged views: a view whose scans
    # failed may report nothing else, but the degradation must still show.
    warnings = reviewed |> Enum.flat_map(& &1.warnings) |> Enum.uniq()
    changes = Enum.reject(reviewed, &unchanged?/1)

    %{changes: changes, summary: summarize(changes), warnings: warnings}
  end

  @doc """
  Run the configured judge over each change in a report.

  Attaches the judge's verdict to every change, replaces the change's
  tier with the judged tier, and recomputes the summary. Run-level
  behavioral findings are handed to the judge as context
  (`:run_behavioral`) but are **not** attributed to any view — they
  stay at the report level, where `mix excessibility.review` prints
  them and gates the exit code on them. A view's tier only reflects
  what that view introduced.
  """
  @spec judge_changes(report(), keyword()) :: report()
  def judge_changes(report, opts \\ []) do
    behavioral = Map.get(report, :behavioral, [])
    judge_opts = Keyword.put(opts, :run_behavioral, behavioral)

    judged =
      Enum.map(report.changes, fn change ->
        verdict = Judge.verdict(change, judge_opts)

        change
        |> Map.put(:verdict, verdict)
        |> Map.put(:tier, verdict.tier)
      end)

    %{report | changes: judged, summary: summarize(judged)}
  end

  @doc """
  Review a single view's baseline-vs-current snapshot pair.
  """
  @spec review_pair(String.t(), String.t(), String.t(), keyword()) :: change()
  def review_pair(view, baseline_html, current_html, opts \\ []) do
    regions = SnapshotDiff.diff(baseline_html, current_html, opts)

    {axe_pair, warnings} = axe_findings_pair(baseline_html, current_html, opts)

    findings =
      content_change_findings(baseline_html, current_html, opts) ++
        new_rule_findings(baseline_html, current_html, axe_pair, opts)

    behavioral =
      case Keyword.get(opts, :timeline) do
        nil -> []
        timeline -> Behavioral.findings(timeline, opts)
      end

    %{
      view: view,
      regions: regions,
      region_count: length(regions),
      findings: findings,
      behavioral: behavioral,
      warnings: warnings,
      tier: tier(findings ++ behavioral)
    }
  end

  # ── Tiering ────────────────────────────────────────────────────────

  @doc """
  The risk tier for a list of findings (accessibility and/or behavioral).

  Driven by the worst severity: a new critical/serious finding is `:block`,
  any other finding is `:review`, none is `:auto`. Regions are reported for
  context but don't escalate on their own.
  """
  @spec tier([map()]) :: tier()
  def tier(findings) do
    severities = Enum.map(findings, & &1.severity)

    cond do
      Enum.any?(severities, &(&1 in [:critical, :serious])) -> :block
      severities != [] -> :review
      true -> :auto
    end
  end

  # `content_change_without_live_region` compares rendered text, so it only
  # means something when both sides rendered the same fixture data. The
  # baseline and current snapshots normally come from two independent
  # `mix test` runs whose fixtures differ (issue #139), so it is opt-in here
  # — unlike `SnapshotDiff.scan_sequence/2`, which diffs consecutive
  # snapshots within one run and keeps it unconditionally.
  defp content_change_findings(baseline_html, current_html, opts) do
    if Keyword.get(opts, :content_diff, false) do
      baseline_html
      |> SnapshotDiff.live_region_findings(current_html, opts)
      |> Enum.map(&Map.put(&1, :source, :live_view_rules))
    else
      []
    end
  end

  # Rule violations (LiveView rules + axe) present in the current snapshot
  # but not the baseline, identified by {rule, selector} so pre-existing
  # issues aren't re-flagged. Counted per fingerprint: a second identical
  # violation behind an existing one is still new.
  defp new_rule_findings(baseline_html, current_html, {axe_baseline, axe_current}, opts) do
    baseline_counts =
      baseline_html
      |> rule_findings(opts)
      |> Kernel.++(axe_baseline)
      |> Enum.frequencies_by(&fingerprint/1)

    {new_findings, _remaining} =
      current_html
      |> rule_findings(opts)
      |> Kernel.++(axe_current)
      |> Enum.flat_map_reduce(baseline_counts, fn finding, counts ->
        key = fingerprint(finding)

        case counts do
          %{^key => n} when n > 0 -> {[], Map.put(counts, key, n - 1)}
          _ -> {[finding], counts}
        end
      end)

    new_findings
  end

  defp rule_findings(html, opts) do
    html
    |> LiveViewRules.scan(opts)
    |> Map.fetch!(:findings)
    |> Enum.map(&Map.put(&1, :source, :live_view_rules))
  end

  # Selectors embed DOM ids, and Phoenix idiomatically derives those from
  # record ids (`id={"row-#{@row.id}"}`) whose values shift between the
  # baseline run and the current run (issue #140), so digit runs are
  # collapsed before comparing. The raw selector stays on the finding for
  # display.
  defp fingerprint(%{rule: rule, selector: selector}), do: {rule, String.replace(selector, ~r/\d+/, "N")}

  # ── axe-core findings ──────────────────────────────────────────────

  # axe findings for both sides of the pair, via the configured scanner
  # (each HTML string is scanned from a temp file as file://). When either
  # scan fails the axe delta would be meaningless — everything on the side
  # that did scan would look new — so both sides are dropped and a warning
  # is surfaced instead.
  defp axe_findings_pair(baseline_html, current_html, opts) do
    if Keyword.get(opts, :axe, true) and baseline_html != current_html do
      case {axe_scan(baseline_html), axe_scan(current_html)} do
        {{:ok, baseline_report}, {:ok, current_report}} ->
          {{axe_findings(baseline_report), axe_findings(current_report)}, []}

        {baseline_result, current_result} ->
          {:error, reason} = Enum.find([baseline_result, current_result], &match?({:error, _}, &1))
          {{[], []}, ["axe scan failed (#{inspect(reason)}) — axe findings are not part of this review"]}
      end
    else
      {{[], []}, []}
    end
  end

  defp axe_scan(html) do
    path = Path.join(System.tmp_dir!(), "excessibility_review_#{System.unique_integer([:positive])}.html")
    File.write!(path, html)

    try do
      scanner_mod().scan("file://" <> path, [])
    after
      File.rm(path)
    end
  end

  # One finding per offending node, so the count-matching delta treats a
  # second identical violation as new — same as the LiveView rules.
  defp axe_findings(report) do
    for violation <- Map.get(report, :violations, []),
        node <- violation.nodes do
      %{
        rule: violation.id,
        selector: Enum.join(node.target, " "),
        severity: violation.impact || :moderate,
        message: violation.help,
        source: :axe
      }
    end
  end

  defp scanner_mod do
    Application.get_env(:excessibility, :scanner_mod, Excessibility.Scanner)
  end

  defp unchanged?(%{region_count: 0, findings: [], behavioral: []}), do: true
  defp unchanged?(_), do: false

  defp summarize(changes) do
    counts = Enum.frequencies_by(changes, & &1.tier)

    %{
      auto: Map.get(counts, :auto, 0),
      review: Map.get(counts, :review, 0),
      block: Map.get(counts, :block, 0)
    }
  end

  # ── Snapshot loading ───────────────────────────────────────────────

  defp matched_pairs(_opts) do
    current_dir = Path.join(output_path(), "html_snapshots")
    baseline_dir = Path.join(output_path(), "baseline")

    current_dir
    |> Path.join("*.html")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))
    |> Enum.flat_map(fn current_path ->
      baseline_path = Path.join(baseline_dir, Path.basename(current_path))

      case File.read(baseline_path) do
        {:ok, baseline_html} ->
          [{Path.basename(current_path), baseline_html, File.read!(current_path)}]

        {:error, _} ->
          []
      end
    end)
  end

  defp output_path do
    Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
  end
end
