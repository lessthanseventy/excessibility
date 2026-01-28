defmodule Excessibility.TelemetryCapture.Analyzer do
  @moduledoc """
  Behaviour for timeline analyzers.

  Analyzers detect patterns across complete timelines and return structured findings.
  Analyzers declare their enricher dependencies via `requires_enrichers/0`.

  ## Example

      defmodule MyApp.CustomAnalyzer do
        @behaviour Excessibility.TelemetryCapture.Analyzer

        def name, do: :custom
        def default_enabled?, do: false
        def requires_enrichers, do: [:memory, :duration]
        def depends_on, do: [:memory]  # runs after memory analyzer

        def analyze(timeline, opts) do
          # Access prior analyzer results via opts[:prior_results]
          prior = Keyword.get(opts, :prior_results, %{})
          memory_stats = get_in(prior, [:memory, :stats])

          %{
            findings: [...],
            stats: %{...}
          }
        end
      end

  ## Callbacks

  - `name/0` - Returns atom identifier for this analyzer
  - `default_enabled?/0` - Whether analyzer runs by default without explicit flag
  - `requires_enrichers/0` - (Optional) List of enricher names this analyzer needs
  - `depends_on/0` - (Optional) List of analyzer names that must run first
  - `analyze/2` - Takes complete timeline and options, returns analysis results

  ## Types

  Analysis results contain:
  - `:findings` - List of issues found (warnings, errors, info)
  - `:stats` - Summary statistics for the analysis
  """

  @callback name() :: atom()
  @callback default_enabled?() :: boolean()
  @callback requires_enrichers() :: [atom()]
  @callback depends_on() :: [atom()]
  @callback analyze(timeline :: map(), opts :: keyword()) :: analysis_result()

  @optional_callbacks requires_enrichers: 0, depends_on: 0

  @type analysis_result :: %{
          findings: [finding()],
          stats: map()
        }

  @type finding :: %{
          severity: :info | :warning | :critical,
          message: String.t(),
          events: [integer()],
          metadata: map()
        }

  @doc """
  Gets required enrichers for an analyzer module.
  Returns empty list if not defined.
  """
  def get_required_enrichers(analyzer_module) do
    if function_exported?(analyzer_module, :requires_enrichers, 0) do
      analyzer_module.requires_enrichers()
    else
      []
    end
  end

  @doc """
  Gets analyzer dependencies for an analyzer module.
  Returns empty list if not defined.
  """
  def get_dependencies(analyzer_module) do
    if function_exported?(analyzer_module, :depends_on, 0) do
      analyzer_module.depends_on()
    else
      []
    end
  end

  @doc """
  Topologically sorts analyzers based on their dependencies.
  Returns analyzers in execution order (dependencies first).
  """
  def sort_by_dependencies(analyzers) do
    # Build dependency graph
    analyzer_map = Map.new(analyzers, fn a -> {a.name(), a} end)

    # Kahn's algorithm for topological sort
    sorted = topological_sort(analyzers, analyzer_map)

    # Preserve original order for analyzers without dependencies
    if sorted == nil do
      # Cycle detected, fall back to original order
      analyzers
    else
      sorted
    end
  end

  defp topological_sort(analyzers, analyzer_map) do
    # Count incoming edges (dependencies) for each analyzer
    in_degree =
      Map.new(analyzers, fn a ->
        deps = a |> get_dependencies() |> Enum.filter(&Map.has_key?(analyzer_map, &1))
        {a.name(), length(deps)}
      end)

    # Start with analyzers that have no dependencies
    queue =
      analyzers
      |> Enum.filter(fn a -> Map.get(in_degree, a.name(), 0) == 0 end)
      |> :queue.from_list()

    do_topological_sort(queue, in_degree, analyzer_map, [])
  end

  defp do_topological_sort(queue, in_degree, analyzer_map, result) do
    case :queue.out(queue) do
      {:empty, _} ->
        # Check if all analyzers are processed
        if length(result) == map_size(analyzer_map) do
          Enum.reverse(result)
          # Cycle detected
        end

      {{:value, analyzer}, rest_queue} ->
        name = analyzer.name()

        # Find analyzers that depend on this one and decrement their in-degree
        {updated_queue, updated_in_degree} =
          analyzer_map
          |> Map.values()
          |> Enum.reduce({rest_queue, in_degree}, &update_dependents(&1, &2, name))

        do_topological_sort(updated_queue, updated_in_degree, analyzer_map, [analyzer | result])
    end
  end

  defp update_dependents(analyzer, {queue, in_degree}, completed_name) do
    deps = get_dependencies(analyzer)

    if completed_name in deps do
      decrement_and_maybe_enqueue(analyzer, queue, in_degree)
    else
      {queue, in_degree}
    end
  end

  defp decrement_and_maybe_enqueue(analyzer, queue, in_degree) do
    new_degree = Map.update!(in_degree, analyzer.name(), &(&1 - 1))

    if Map.get(new_degree, analyzer.name()) == 0 do
      {:queue.in(analyzer, queue), new_degree}
    else
      {queue, new_degree}
    end
  end
end
