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

  alias Excessibility.TelemetryCapture.Analyzer

  # A list going from empty to a single element is normal (issue #142): an
  # unbounded ratio off a zero baseline (`0 → 1 = ∞x`) isn't a useful
  # severity input. A from-zero list only warns once it reaches a size worth
  # a second look; a genuinely large from-zero list still trips the
  # pagination critical below.
  @appeared_min 10

  def name, do: :data_growth
  def default_enabled?, do: true
  def requires_enrichers, do: [:collection_size]

  def analyze(%{timeline: []}, _opts) do
    %{findings: [], stats: %{}}
  end

  def analyze(%{timeline: timeline}, _opts) do
    # Track each list's size within a single view; a journey test interleaves
    # LiveViews, so a path that goes `0 → 1` in one view with unrelated events
    # between must not be compared across the gap (issue #142).
    findings =
      timeline
      |> Analyzer.group_by_view()
      |> Enum.flat_map(fn events -> detect_growth(events, discover_list_paths(events)) end)

    stats = calculate_stats(discover_list_paths(timeline), timeline)

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

      warning_growth?(growth_multiplier, last_size) ->
        [build_finding(:warning, path, sizes, growth_multiplier, last_size, sequences)]

      true ->
        []
    end
  end

  defp critical_growth?(growth_multiplier, max_step_growth, last_size) do
    max_step_growth >= 10 or
      (last_size > 100 and (growth_multiplier == :infinity or growth_multiplier >= 3))
  end

  # A from-zero list (`:infinity` multiplier) only warns once it has grown to
  # a size worth a second look — `0 → 1` is just an item appearing (#142).
  defp warning_growth?(:infinity, last_size), do: last_size >= @appeared_min
  defp warning_growth?(growth_multiplier, _last_size), do: growth_multiplier >= 3

  defp build_finding(severity, path, sizes, growth_multiplier, last_size, sequences) do
    suggest_pagination? = severity == :critical and last_size > 100
    growth_pattern = detect_growth_pattern(sizes)
    suggestion = build_suggestion(growth_pattern, last_size, suggest_pagination?)

    %{
      severity: severity,
      message: build_growth_message(path, sizes, growth_multiplier, suggestion),
      events: sequences,
      metadata: build_metadata(path, sizes, growth_multiplier, suggest_pagination?, suggestion)
    }
  end

  defp detect_growth_pattern(sizes) do
    monotonic? =
      sizes
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.all?(fn [a, b] -> b >= a end)

    if monotonic?, do: :append_only, else: :mixed
  end

  defp build_suggestion(growth_pattern, last_size, suggest_pagination?) do
    cond do
      suggest_pagination? and growth_pattern == :append_only ->
        "consider `temporary_assigns` if items are rendered once, or Streams for individual updates, or pagination"

      growth_pattern == :append_only and last_size > 50 ->
        "consider `temporary_assigns` if items are rendered once, or Streams for individual updates"

      growth_pattern == :append_only ->
        "consider `temporary_assigns` if items are rendered once"

      suggest_pagination? ->
        "consider pagination or lazy loading"

      true ->
        nil
    end
  end

  defp build_metadata(path, sizes, growth_multiplier, suggest_pagination?, suggestion) do
    base = %{
      list_name: path,
      sizes: sizes,
      growth_multiplier: format_growth_multiplier(growth_multiplier)
    }

    base = if suggest_pagination?, do: Map.put(base, :suggest_pagination?, true), else: base
    if suggestion, do: Map.put(base, :suggestion, suggestion), else: base
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

  defp build_growth_message(path, sizes, multiplier, suggestion) do
    path_str = to_string(path)
    sizes_str = Enum.map_join(sizes, " → ", &to_string/1)
    multiplier_str = format_growth_multiplier(multiplier)

    base = "List '#{path_str}' growing: #{sizes_str} (#{multiplier_str}x)"

    if suggestion do
      base <> " — " <> suggestion
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
