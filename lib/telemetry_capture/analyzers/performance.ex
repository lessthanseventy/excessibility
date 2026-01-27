defmodule Excessibility.TelemetryCapture.Analyzers.Performance do
  @moduledoc """
  Analyzes performance patterns across timeline events.

  Detects:
  - Slow events using adaptive thresholds (> mean + 2σ)
  - Bottlenecks (events taking >50% of total time)
  - Very slow events (>1000ms)

  Uses data from the Duration enricher (event_duration_ms) to identify
  performance issues.

  ## Algorithm

  1. Calculate baseline stats (mean, std deviation)
  2. Detect slow events:
     - Warning: Duration > mean + 2σ
     - Critical: Duration > 1000ms OR > mean + 3σ
  3. Detect bottlenecks: Events taking >50% of total time

  ## Output

  Returns findings and statistics:

      %{
        findings: [
          %{
            severity: :warning,
            message: "Slow event (250ms, 5x average)",
            events: [3],
            metadata: %{duration_ms: 250, multiplier: 5.0}
          }
        ],
        stats: %{
          min_duration: 10,
          max_duration: 250,
          avg_duration: 50,
          total_duration: 500
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :performance
  def default_enabled?, do: true

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    durations = extract_durations(timeline)

    if Enum.empty?(durations) do
      %{findings: [], stats: %{}}
    else
      stats = calculate_stats(durations)
      findings = detect_issues(timeline, stats)

      %{
        findings: findings,
        stats: stats
      }
    end
  end

  defp extract_durations(timeline) do
    timeline
    |> Enum.map(&Map.get(&1, :event_duration_ms))
    |> Enum.reject(&is_nil/1)
  end

  defp calculate_stats([]), do: %{}

  defp calculate_stats(durations) do
    total = Enum.sum(durations)
    count = length(durations)
    avg = total / count

    sorted = Enum.sort(durations)
    min_val = List.first(sorted)
    max_val = List.last(sorted)

    std_dev = calculate_std_dev(durations, avg)

    %{
      min_duration: min_val,
      max_duration: max_val,
      avg_duration: round(avg),
      total_duration: total,
      std_dev: round(std_dev)
    }
  end

  defp calculate_std_dev(values, mean) do
    variance =
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp detect_issues(timeline, stats) do
    slow_findings = detect_slow_events(timeline, stats)
    bottleneck_findings = detect_bottlenecks(timeline, stats)

    slow_findings ++ bottleneck_findings
  end

  defp detect_slow_events(timeline, stats) do
    threshold_warning = stats.avg_duration + 2 * stats.std_dev
    threshold_critical = stats.avg_duration + 3 * stats.std_dev

    Enum.flat_map(timeline, fn event ->
      check_event_duration(event, stats, threshold_warning, threshold_critical)
    end)

    # Critical: >1000ms OR > mean + 3σ
    # Warning: > mean + 2σ
  end

  defp check_event_duration(event, stats, threshold_warning, threshold_critical) do
    duration = Map.get(event, :event_duration_ms)

    if is_nil(duration) do
      []
    else
      # Ensure multiplier is always a float to avoid Float.round/2 errors
      multiplier = if stats.avg_duration > 0, do: duration / stats.avg_duration, else: 0.0

      cond do
        duration > 1000 or duration > threshold_critical ->
          [
            %{
              severity: :critical,
              message: "Very slow event (#{duration}ms, #{format_multiplier(multiplier)}x average)",
              events: [event.sequence],
              metadata: %{duration_ms: duration, multiplier: round_float(multiplier, 1)}
            }
          ]

        duration > threshold_warning ->
          [
            %{
              severity: :warning,
              message: "Slow event (#{duration}ms, #{format_multiplier(multiplier)}x average)",
              events: [event.sequence],
              metadata: %{duration_ms: duration, multiplier: round_float(multiplier, 1)}
            }
          ]

        true ->
          []
      end
    end
  end

  defp detect_bottlenecks(timeline, stats) do
    threshold = stats.total_duration * 0.5

    Enum.flat_map(timeline, fn event ->
      duration = Map.get(event, :event_duration_ms)

      if is_nil(duration) or duration <= threshold do
        []
      else
        percentage = round(duration / stats.total_duration * 100)

        [
          %{
            severity: :critical,
            message: "Performance bottleneck: event took #{duration}ms (#{percentage}% of total time)",
            events: [event.sequence],
            metadata: %{duration_ms: duration, percentage: percentage}
          }
        ]
      end
    end)
  end

  defp format_multiplier(mult) when mult >= 1, do: round_float(mult, 1)
  defp format_multiplier(mult), do: round_float(mult, 2)

  # Safely round numbers to floats, handling both integer and float inputs
  defp round_float(num, _precision) when is_integer(num), do: num * 1.0
  defp round_float(num, precision) when is_float(num), do: Float.round(num, precision)
end
