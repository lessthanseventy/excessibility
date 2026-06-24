defmodule Excessibility.Review do
  @moduledoc """
  A blast-radius report for a snapshot run, measured against the baseline.

  Where `mix excessibility` checks each snapshot in isolation, a review
  asks a sharper question: *what did this change actually do?* It diffs
  every current snapshot against its baseline (the known-good/`main`
  state) and, per view, reports:

    * the rendered regions that changed (via `Excessibility.SnapshotDiff`)
    * the accessibility findings this change **newly introduced** — rule
      violations present now but not in the baseline (a finding-delta), plus
      content that changed without an `aria-live` announcement
    * a risk **tier** — `:auto`, `:review`, or `:block`

  The tier is a transparent heuristic over the new findings; a smarter
  judge can be layered on top of the same report. Because it diffs against
  the baseline rather than two git refs, it runs from an ordinary
  `mix test` + baseline, with no worktree gymnastics.
  """

  alias Excessibility.LiveViewRules
  alias Excessibility.Review.Behavioral
  alias Excessibility.SnapshotDiff

  @type tier :: :auto | :review | :block

  @type change :: %{
          view: String.t(),
          regions: [SnapshotDiff.region()],
          region_count: non_neg_integer(),
          findings: [map()],
          behavioral: [Behavioral.finding()],
          tier: tier()
        }

  @type report :: %{
          changes: [change()],
          behavioral: [Behavioral.finding()],
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
    changes =
      pairs
      |> Enum.map(fn {view, baseline, current} -> review_pair(view, baseline, current, opts) end)
      |> Enum.reject(&unchanged?/1)

    %{changes: changes, summary: summarize(changes)}
  end

  @doc """
  Review a single view's baseline-vs-current snapshot pair.
  """
  @spec review_pair(String.t(), String.t(), String.t(), keyword()) :: change()
  def review_pair(view, baseline_html, current_html, opts \\ []) do
    regions = SnapshotDiff.diff(baseline_html, current_html, opts)

    findings =
      SnapshotDiff.live_region_findings(baseline_html, current_html, opts) ++
        new_rule_findings(baseline_html, current_html, opts)

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

  # Rule violations present in the current snapshot but not the baseline,
  # identified by {rule, selector} so pre-existing issues aren't re-flagged.
  defp new_rule_findings(baseline_html, current_html, opts) do
    baseline_keys =
      baseline_html
      |> LiveViewRules.scan(opts)
      |> Map.fetch!(:findings)
      |> MapSet.new(&fingerprint/1)

    current_html
    |> LiveViewRules.scan(opts)
    |> Map.fetch!(:findings)
    |> Enum.reject(&MapSet.member?(baseline_keys, fingerprint(&1)))
  end

  defp fingerprint(%{rule: rule, selector: selector}), do: {rule, selector}

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
