defmodule Excessibility.TelemetryCapture.Analyzers.EctoQueryAnalysis do
  @moduledoc """
  Analyzes Ecto query patterns across timeline events.

  Replaces the old N+1 analyzer. Uses actual query data from the
  ecto_queries enricher instead of just counting NotLoaded associations.

  Detects:
  - Excessive queries per event (>5 queries)
  - N+1 patterns (multiple SELECTs on same table in one event)
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

  @excessive_query_threshold 5
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
    severity = if count > 10, do: :critical, else: :warning

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

  defp detect_n_plus_one(event, queries) when length(queries) >= @n_plus_one_threshold do
    queries
    |> Enum.filter(&(&1.operation == :select))
    |> Enum.group_by(& &1.source)
    |> Enum.flat_map(fn {source, source_queries} ->
      count = length(source_queries)

      if count >= @n_plus_one_threshold do
        total_ms = source_queries |> Enum.map(& &1.duration_ms) |> Enum.sum()

        [
          %{
            severity: :critical,
            message:
              "#{count} of #{length(queries)} queries are SELECT on \"#{source}\" in #{event.event} (N+1 pattern) — consider preloading or batching",
            events: [event.sequence],
            metadata: %{
              source: source,
              count: count,
              total_ms: Float.round(total_ms * 1.0, 2),
              pattern: :n_plus_one
            }
          }
        ]
      else
        []
      end
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
        queries_by_source:
          all_queries |> Enum.group_by(& &1.source) |> Map.new(fn {k, v} -> {k, length(v)} end)
      }
    end
  end

  defp format_ms(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
  defp format_ms(ms), do: "#{ms}ms"
end
