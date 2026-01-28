defmodule Excessibility.TelemetryCapture.Analyzers.DataGrowth do
  @moduledoc """
  Analyzes data growth patterns across timeline events.

  Detects:
  - Unbounded list growth (3x+ growth)
  - Rapid growth (10x+ in single transition)
  - Large growing lists (suggest pagination)

  Uses data from the CollectionSize enricher (list_sizes) to track
  how list sizes change over time.

  ## Algorithm

  1. Track each list's size across events
  2. Detect significant growth:
     - Warning: 3x+ growth overall
     - Critical: 10x+ growth in single step OR list exceeds 100 items
  3. Suggest pagination for large growing lists (>100 items)

  ## Output

  Returns findings and statistics:

      %{
        findings: [
          %{
            severity: :warning,
            message: "List 'products' growing: 10 → 50 → 200 (20x)",
            events: [1, 2, 3],
            metadata: %{
              list_name: :products,
              sizes: [10, 50, 200],
              growth_multiplier: 20.0
            }
          }
        ],
        stats: %{
          growing_lists: [:products, :users]
        }
      }
  """

  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :data_growth
  def default_enabled?, do: true
  def requires_enrichers, do: [:collection_size]

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    list_paths = discover_list_paths(timeline)
    findings = detect_growth(timeline, list_paths)
    stats = calculate_stats(list_paths, timeline)

    %{
      findings: findings,
      stats: stats
    }
  end

  defp discover_list_paths(timeline) do
    timeline
    |> Enum.flat_map(fn event ->
      event
      |> Map.get(:list_sizes, %{})
      |> Map.keys()
    end)
    |> Enum.uniq()
  end

  defp detect_growth(timeline, list_paths) do
    Enum.flat_map(list_paths, fn path ->
      sizes = extract_sizes_for_path(timeline, path)
      analyze_list_growth(path, sizes, timeline)
    end)
  end

  defp extract_sizes_for_path(timeline, path) do
    timeline
    |> Enum.map(fn event ->
      event
      |> Map.get(:list_sizes, %{})
      |> Map.get(path)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp analyze_list_growth(_path, sizes, _timeline) when length(sizes) < 2, do: []

  defp analyze_list_growth(path, sizes, timeline) do
    first_size = List.first(sizes)
    last_size = List.last(sizes)

    # Skip if list is shrinking or not growing
    if last_size <= first_size do
      []
    else
      growth_multiplier = calculate_growth_multiplier(first_size, last_size)
      max_single_step_growth = calculate_max_step_growth(sizes)
      sequences = get_sequences_for_path(timeline, path)

      maybe_build_finding(path, sizes, growth_multiplier, max_single_step_growth, last_size, sequences)
    end
  end

  defp calculate_growth_multiplier(first_size, last_size) when first_size > 0 do
    last_size / first_size
  end

  defp calculate_growth_multiplier(_first_size, _last_size) do
    # When starting from 0, treat any growth as significant
    :infinity
  end

  defp maybe_build_finding(path, sizes, growth_multiplier, max_step_growth, last_size, sequences) do
    cond do
      critical_growth?(growth_multiplier, max_step_growth, last_size) ->
        [build_finding(:critical, path, sizes, growth_multiplier, last_size, sequences)]

      warning_growth?(growth_multiplier) ->
        [build_finding(:warning, path, sizes, growth_multiplier, last_size, sequences)]

      true ->
        []
    end
  end

  defp critical_growth?(growth_multiplier, max_step_growth, last_size) do
    max_step_growth >= 10 or
      (last_size > 100 and (growth_multiplier == :infinity or growth_multiplier >= 3))
  end

  defp warning_growth?(growth_multiplier) do
    growth_multiplier == :infinity or growth_multiplier >= 3
  end

  defp build_finding(severity, path, sizes, growth_multiplier, last_size, sequences) do
    suggest_pagination? = severity == :critical and last_size > 100

    %{
      severity: severity,
      message: build_growth_message(path, sizes, growth_multiplier, suggest_pagination?),
      events: sequences,
      metadata: build_metadata(path, sizes, growth_multiplier, suggest_pagination?)
    }
  end

  defp build_metadata(path, sizes, growth_multiplier, suggest_pagination?) do
    base = %{
      list_name: path,
      sizes: sizes,
      growth_multiplier: format_growth_multiplier(growth_multiplier)
    }

    if suggest_pagination? do
      Map.put(base, :suggest_pagination?, true)
    else
      base
    end
  end

  defp calculate_max_step_growth([_single]), do: 1.0

  defp calculate_max_step_growth(sizes) do
    sizes
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      if a > 0, do: b / a, else: 1.0
    end)
    |> Enum.max()
  end

  defp get_sequences_for_path(timeline, path) do
    timeline
    |> Enum.filter(fn event ->
      event
      |> Map.get(:list_sizes, %{})
      |> Map.has_key?(path)
    end)
    |> Enum.map(& &1.sequence)
  end

  defp format_growth_multiplier(:infinity), do: "∞"

  defp format_growth_multiplier(multiplier) when is_number(multiplier) do
    Float.round(multiplier, 1)
  end

  defp build_growth_message(path, sizes, multiplier, suggest_pagination?) do
    path_str = to_string(path)
    sizes_str = Enum.map_join(sizes, " → ", &to_string/1)
    multiplier_str = format_growth_multiplier(multiplier)

    base = "List '#{path_str}' growing: #{sizes_str} (#{multiplier_str}x)"

    if suggest_pagination? do
      base <> " - consider pagination or lazy loading"
    else
      base
    end
  end

  defp calculate_stats([], _timeline), do: %{}

  defp calculate_stats(list_paths, timeline) do
    growing =
      Enum.filter(list_paths, fn path ->
        sizes = extract_sizes_for_path(timeline, path)

        if length(sizes) >= 2 do
          List.last(sizes) > List.first(sizes)
        else
          false
        end
      end)

    %{
      growing_lists: growing
    }
  end
end
