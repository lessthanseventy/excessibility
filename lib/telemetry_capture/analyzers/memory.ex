defmodule Excessibility.TelemetryCapture.Analyzers.Memory do
  @moduledoc """
  Analyzes memory usage patterns across timeline events.

  Detects:
  - Memory bloat (large growth between events)
  - Memory leaks (3+ consecutive increases)

  Uses adaptive thresholds based on timeline statistics to avoid
  false positives and work across different test sizes.

  ## Algorithm

  1. Calculate baseline stats (mean, median, std deviation)
  2. Calculate median delta between events
  3. Detect outliers:
     - Warning: Growth > 3x median delta
     - Critical: Growth > 10x median delta OR size > mean + 2std_dev
  4. Detect leaks: 3+ consecutive increases

  ## Output

  Returns findings and statistics:

      %{
        findings: [
          %{
            severity: :warning,
            message: "Memory grew 5.2x between events (45 KB → 234 KB)",
            events: [3, 4],
            metadata: %{growth_multiplier: 5.2, delta_bytes: 189000}
          }
        ],
        stats: %{min: 2300, max: 890000, avg: 145000, median_delta: 12000}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :memory
  def default_enabled?, do: true
  def requires_enrichers, do: [:memory]

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    memory_sizes = extract_memory_sizes(timeline)

    stats = calculate_stats(memory_sizes)
    findings = detect_issues(timeline, stats)

    %{
      findings: findings,
      stats: stats
    }
  end

  defp extract_memory_sizes(timeline) do
    Enum.map(timeline, & &1.memory_size)
  end

  defp calculate_stats([]), do: %{}

  defp calculate_stats(sizes) do
    sorted = Enum.sort(sizes)
    count = length(sizes)

    min = List.first(sorted)
    max = List.last(sorted)
    avg = Enum.sum(sizes) / count

    median = calculate_median(sorted)
    std_dev = calculate_std_dev(sizes, avg)

    deltas = calculate_deltas(sizes)
    median_delta = if Enum.empty?(deltas), do: 0, else: calculate_median(Enum.sort(deltas))

    %{
      min: min,
      max: max,
      avg: round(avg),
      median: median,
      std_dev: round(std_dev),
      median_delta: median_delta
    }
  end

  defp calculate_median(sorted_list) do
    count = length(sorted_list)
    mid = div(count, 2)

    if_result =
      if rem(count, 2) == 0 do
        (Enum.at(sorted_list, mid - 1) + Enum.at(sorted_list, mid)) / 2
      else
        Enum.at(sorted_list, mid)
      end

    round(if_result)
  end

  defp calculate_std_dev(values, mean) do
    variance =
      values
      |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp calculate_deltas(sizes) do
    sizes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> abs(b - a) end)
  end

  defp detect_issues(_timeline, stats) when map_size(stats) == 0, do: []

  defp detect_issues(timeline, stats) do
    bloat_findings = detect_bloat(timeline, stats)
    leak_findings = detect_leaks(timeline, stats)

    bloat_findings ++ leak_findings
  end

  defp detect_bloat(timeline, stats) do
    timeline
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [prev, curr] ->
      delta = curr.memory_size - prev.memory_size
      multiplier = if prev.memory_size > 0, do: delta / prev.memory_size, else: 0

      cond do
        # Critical: 10x growth, or 10x median delta, or > mean + 2std_dev
        multiplier >= 10 or delta > stats.median_delta * 10 or
            curr.memory_size > stats.avg + 2 * stats.std_dev ->
          [
            %{
              severity: :critical,
              message:
                "Memory grew #{format_multiplier(multiplier)}x between events (#{format_bytes(prev.memory_size)} → #{format_bytes(curr.memory_size)})",
              events: [prev.sequence, curr.sequence],
              metadata: %{growth_multiplier: Float.round(multiplier, 1), delta_bytes: delta}
            }
          ]

        # Warning: 3x growth or 3x median delta
        multiplier >= 3 or delta > stats.median_delta * 3 ->
          [
            %{
              severity: :warning,
              message:
                "Memory grew #{format_multiplier(multiplier)}x between events (#{format_bytes(prev.memory_size)} → #{format_bytes(curr.memory_size)})",
              events: [prev.sequence, curr.sequence],
              metadata: %{growth_multiplier: Float.round(multiplier, 1), delta_bytes: delta}
            }
          ]

        true ->
          []
      end
    end)
  end

  defp detect_leaks(timeline, stats) do
    timeline
    |> Enum.chunk_every(3, 1, :discard)
    |> Enum.flat_map(fn chunk ->
      if significant_consecutive_increases?(chunk, stats) do
        sequences = Enum.map(chunk, & &1.sequence)
        sizes = Enum.map(chunk, & &1.memory_size)

        [
          %{
            severity: :critical,
            message:
              "Possible memory leak: consecutive growth in events #{Enum.join(sequences, ", ")} (#{Enum.map_join(sizes, " → ", &format_bytes/1)})",
            events: sequences,
            metadata: %{sizes: sizes}
          }
        ]
      else
        []
      end
    end)
  end

  defp significant_consecutive_increases?([a, b, c], stats) do
    # All must be increasing
    increasing? = a.memory_size < b.memory_size and b.memory_size < c.memory_size

    if increasing? do
      # At least one increase must be > median_delta to avoid flagging tiny healthy growth
      delta1 = b.memory_size - a.memory_size
      delta2 = c.memory_size - b.memory_size
      threshold = stats.median_delta

      delta1 > threshold or delta2 > threshold
    else
      false
    end
  end

  defp format_multiplier(mult) when mult >= 1, do: Float.round(mult, 1)
  defp format_multiplier(mult), do: Float.round(mult, 2)

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
