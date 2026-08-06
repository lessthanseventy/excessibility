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

  alias Excessibility.TelemetryCapture.Analyzer

  # A ratio off a tiny denominator (issue #142: a 220-byte freshly-mounted
  # view followed by a 109 KB loaded view reads as "507x growth") is noise:
  # 109 KB is an ordinary LiveView heap. A memory finding therefore requires
  # the larger side to clear an absolute floor, regardless of ratio.
  @min_notable_bytes 262_144

  # The floor gates the size, but not the growth: a run that holds steady at
  # 1.3 MB is a global outlier that clears the floor yet grew 0% (issue #146,
  # reported as "grew 1.0x"). A "grew Nx" finding therefore also requires the
  # ratio to clear a minimum — a flat or shrinking transition isn't bloat.
  @min_growth_factor 1.2

  def name, do: :memory
  def default_enabled?, do: true
  def requires_enrichers, do: [:assign_sizes]

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
    Enum.map(timeline, & &1.total_memory)
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

  # Consecutive-event comparisons run per view: a journey test interleaves
  # LiveViews, so adjacent events can belong to different processes (#142).
  defp detect_bloat(timeline, stats) do
    timeline
    |> Analyzer.group_by_view()
    |> Enum.flat_map(&Enum.chunk_every(&1, 2, 1, :discard))
    |> Enum.flat_map(fn [prev, curr] -> bloat_for_pair(prev, curr, stats) end)
  end

  defp bloat_for_pair(prev, curr, stats) do
    delta = curr.total_memory - prev.total_memory
    # `factor` (curr/prev) is what the message reports, so "grew 1.5x" means
    # the heap is 1.5x its previous size — not the confusing "grew 0.5x" that
    # delta/prev produced. The thresholds themselves use delta/prev.
    factor = growth_factor(prev.total_memory, curr.total_memory)

    cond do
      # An ordinary-sized heap never bloats on ratio alone.
      curr.total_memory < @min_notable_bytes -> []
      # A flat or shrinking transition isn't growth, even at a large size.
      not growth?(factor) -> []
      critical_bloat?(prev, curr, delta, stats) -> [bloat_finding(:critical, prev, curr, factor, delta)]
      warning_bloat?(prev, delta, stats) -> [bloat_finding(:warning, prev, curr, factor, delta)]
      true -> []
    end
  end

  # curr/prev, with sentinels for the (near-impossible) zero-previous case.
  defp growth_factor(prev, curr) when prev > 0, do: curr / prev
  defp growth_factor(_prev, curr) when curr > 0, do: :infinity
  defp growth_factor(_prev, _curr), do: 1.0

  defp growth?(:infinity), do: true
  defp growth?(factor), do: factor >= @min_growth_factor

  # Critical: 10x growth, or 10x median delta, or beyond mean + 2 std_dev.
  defp critical_bloat?(prev, curr, delta, stats) do
    ratio(delta, prev.total_memory) >= 10 or delta > stats.median_delta * 10 or
      curr.total_memory > stats.avg + 2 * stats.std_dev
  end

  # Warning: 3x growth or 3x median delta.
  defp warning_bloat?(prev, delta, stats) do
    ratio(delta, prev.total_memory) >= 3 or delta > stats.median_delta * 3
  end

  defp ratio(_delta, 0), do: 0
  defp ratio(delta, prev), do: delta / prev

  defp bloat_finding(severity, prev, curr, factor, delta) do
    %{
      severity: severity,
      message:
        "Memory grew #{format_multiplier(factor)}x between events (#{format_bytes(prev.total_memory)} → #{format_bytes(curr.total_memory)})",
      events: [prev.sequence, curr.sequence],
      metadata: %{growth_multiplier: format_multiplier(factor), delta_bytes: delta}
    }
  end

  defp detect_leaks(timeline, stats) do
    timeline
    |> Analyzer.group_by_view()
    |> Enum.flat_map(&Enum.chunk_every(&1, 3, 1, :discard))
    |> Enum.flat_map(fn chunk ->
      if significant_consecutive_increases?(chunk, stats) and notable_chunk?(chunk) do
        sequences = Enum.map(chunk, & &1.sequence)
        sizes = Enum.map(chunk, & &1.total_memory)

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

  # Grouping by view can expose a monotonic run that the interleaving used
  # to mask; a run of ordinary-sized heaps still isn't a leak worth flagging.
  defp notable_chunk?(chunk) do
    chunk |> Enum.map(& &1.total_memory) |> Enum.max() >= @min_notable_bytes
  end

  defp significant_consecutive_increases?([a, b, c], stats) do
    # All must be increasing
    increasing? = a.total_memory < b.total_memory and b.total_memory < c.total_memory

    if increasing? do
      # At least one increase must be > median_delta to avoid flagging tiny healthy growth
      delta1 = b.total_memory - a.total_memory
      delta2 = c.total_memory - b.total_memory
      threshold = stats.median_delta

      delta1 > threshold or delta2 > threshold
    else
      false
    end
  end

  defp format_multiplier(:infinity), do: "∞"
  defp format_multiplier(mult) when mult >= 1, do: Float.round(mult, 1)
  defp format_multiplier(mult), do: Float.round(mult, 2)

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
end
