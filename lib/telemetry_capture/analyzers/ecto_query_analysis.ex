defmodule Excessibility.TelemetryCapture.Analyzers.EctoQueryAnalysis do
  @moduledoc """
  Analyzes Ecto query patterns across timeline events.

  Replaces the old N+1 analyzer. Uses actual query data from the
  ecto_queries enricher instead of just counting NotLoaded associations.

  Detects:
  - Excessive queries per event (>10 queries)
  - N+1 patterns (multiple SELECTs of the same query shape/fingerprint in one event)
  - Slow individual queries (>100ms)
  - Slow total query time per event (>500ms)

  ## Output

      %{
        findings: [
          %{
            severity: :critical,
            message: "handle_event:load_items triggered 30 queries in 142ms...",
            events: [1],
            metadata: %{query_count: 30, total_ms: 142.0, pattern: :n_plus_one}
          }
        ],
        stats: %{total_queries: 30, total_query_ms: 142.0, max_queries_per_event: 30}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  # Conservative floor: real Phoenix mounts with nested preloads routinely run
  # more than a handful of queries, so an absolute count only signals a problem
  # well above that (issue #151). The shape-based N+1 detector carries the
  # precise signal; this is a coarse backstop for genuinely high volume.
  @excessive_query_threshold 10
  @excessive_critical_threshold 20
  @n_plus_one_threshold 3
  @slow_query_ms 100
  @slow_total_ms 500

  def name, do: :ecto_query_analysis
  def default_enabled?, do: true
  def requires_enrichers, do: [:ecto_queries]

  def analyze(%{timeline: []}, _opts), do: %{findings: [], stats: %{}}

  def analyze(%{timeline: timeline}, _opts) do
    findings = Enum.flat_map(timeline, &analyze_event/1)
    stats = calculate_stats(timeline)

    %{findings: findings, stats: stats}
  end

  defp analyze_event(event) do
    queries = Map.get(event, :ecto_queries, [])
    query_count = length(queries)
    total_ms = Map.get(event, :ecto_total_query_ms, 0)

    detect_excessive_queries(event, query_count, total_ms) ++
      detect_n_plus_one(event, queries) ++
      detect_slow_queries(event, queries) ++
      detect_slow_total(event, total_ms, query_count)
  end

  defp detect_excessive_queries(event, count, total_ms) when count > @excessive_query_threshold do
    severity = if count > @excessive_critical_threshold, do: :critical, else: :warning

    [
      %{
        severity: severity,
        message: "#{event.event} triggered #{count} queries in #{format_ms(total_ms)}",
        events: [event.sequence],
        metadata: %{query_count: count, total_ms: total_ms, pattern: :excessive}
      }
    ]
  end

  defp detect_excessive_queries(_event, _count, _total_ms), do: []

  # Group repeated SELECTs by query *fingerprint* rather than by source table.
  # Two different SELECTs on the same table are distinct N+1 candidates, and
  # identical SELECTs group together even across bind-arity differences. The
  # shared `QueryEvidence.repeated/2` also tolerates string `operation` values
  # from a reloaded `timeline.json` (issue #151).
  defp detect_n_plus_one(event, queries) when length(queries) >= @n_plus_one_threshold do
    queries
    |> Excessibility.QueryEvidence.repeated(min_repetitions: @n_plus_one_threshold)
    |> Enum.map(fn rep ->
      total_ms =
        queries
        |> Enum.filter(&(Map.get(&1, :fingerprint) == rep.fingerprint))
        |> Enum.map(&Map.get(&1, :duration_ms, 0))
        |> Enum.sum()

      %{
        severity: :warning,
        message:
          "#{rep.source} #{rep.operation} query repeated #{rep.repetitions}x (same query shape) in #{event.event} (N+1 pattern) — consider preloading or batching",
        events: [event.sequence],
        metadata: %{
          source: rep.source,
          fingerprint: rep.fingerprint,
          count: rep.repetitions,
          total_ms: Float.round(total_ms * 1.0, 2),
          pattern: :n_plus_one
        }
      }
    end)
  end

  defp detect_n_plus_one(_event, _queries), do: []

  defp detect_slow_queries(event, queries) do
    Enum.flat_map(queries, fn query ->
      if query.duration_ms > @slow_query_ms do
        [
          %{
            severity: :warning,
            message:
              "Slow query on \"#{query.source}\" took #{format_ms(query.duration_ms)} in #{event.event} — consider caching or async loading",
            events: [event.sequence],
            metadata: %{
              source: query.source,
              duration_ms: query.duration_ms,
              query: query.query,
              pattern: :slow_query
            }
          }
        ]
      else
        []
      end
    end)
  end

  defp detect_slow_total(event, total_ms, query_count) when total_ms > @slow_total_ms do
    [
      %{
        severity: :critical,
        message:
          "#{event.event} ran #{query_count} queries totaling #{format_ms(total_ms)} — consider reducing query count or caching",
        events: [event.sequence],
        metadata: %{query_count: query_count, total_ms: total_ms, pattern: :slow_total}
      }
    ]
  end

  defp detect_slow_total(_event, _total_ms, _count), do: []

  defp calculate_stats(timeline) do
    all_queries = Enum.flat_map(timeline, &Map.get(&1, :ecto_queries, []))
    query_counts = Enum.map(timeline, &Map.get(&1, :ecto_query_count, 0))

    if Enum.empty?(all_queries) do
      %{}
    else
      total_ms = all_queries |> Enum.map(& &1.duration_ms) |> Enum.sum()

      %{
        total_queries: length(all_queries),
        total_query_ms: Float.round(total_ms * 1.0, 2),
        max_queries_per_event: Enum.max(query_counts, fn -> 0 end),
        queries_by_source: all_queries |> Enum.group_by(& &1.source) |> Map.new(fn {k, v} -> {k, length(v)} end)
      }
    end
  end

  defp format_ms(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
  defp format_ms(ms), do: "#{ms}ms"
end
