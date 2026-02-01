defmodule Excessibility.MCP.Resources.Analyzer do
  @moduledoc """
  MCP resource for accessing analyzer documentation.

  Provides detailed documentation for each analyzer including:
  - What patterns it detects
  - How to interpret findings
  - How to fix common issues
  - Configuration options
  """

  @behaviour Excessibility.MCP.Resource

  alias Excessibility.TelemetryCapture.Analyzer
  alias Excessibility.TelemetryCapture.Registry

  @impl true
  def uri_pattern, do: "analyzer://{name}"

  @impl true
  def name, do: "analyzer"

  @impl true
  def description, do: "Timeline analyzer documentation and configuration"

  @impl true
  def mime_type, do: "text/markdown"

  @impl true
  def list do
    Enum.map(Registry.get_all_analyzers(), &analyzer_to_resource/1)
  end

  @impl true
  def read("analyzer://" <> name) do
    case Registry.get_analyzer(String.to_atom(name)) do
      nil ->
        {:error, "Analyzer not found: #{name}"}

      analyzer ->
        {:ok, generate_documentation(analyzer)}
    end
  end

  def read(uri) do
    {:error, "Invalid analyzer URI: #{uri}"}
  end

  defp analyzer_to_resource(analyzer) do
    name_str = to_string(analyzer.name())

    %{
      "uri" => "analyzer://#{name_str}",
      "name" => name_str,
      "description" => get_short_description(analyzer),
      "mimeType" => "text/markdown"
    }
  end

  defp get_short_description(analyzer) do
    case Code.fetch_docs(analyzer) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        doc
        |> String.split("\n\n")
        |> List.first()
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
        |> String.slice(0, 100)

      _ ->
        analyzer_short_descriptions()[analyzer.name()] ||
          "Analyzer: #{analyzer.name()}"
    end
  end

  defp generate_documentation(analyzer) do
    name = analyzer.name()
    default? = analyzer.default_enabled?()
    enrichers = Analyzer.get_required_enrichers(analyzer)
    dependencies = Analyzer.get_dependencies(analyzer)

    doc = get_module_doc(analyzer)
    detects = get_detects(analyzer)
    {how_to_fix, examples} = get_fix_info(name)

    """
    # #{Macro.camelize(to_string(name))} Analyzer

    #{doc}

    ## Status

    - **Default Enabled**: #{if default?, do: "Yes", else: "No (opt-in)"}
    - **Required Enrichers**: #{format_list(enrichers)}
    - **Dependencies**: #{format_list(dependencies)}

    ## What It Detects

    #{format_bullet_list(detects)}

    ## How to Fix

    #{how_to_fix}

    ## Examples

    #{examples}

    ## Usage

    ```bash
    # Run with this analyzer
    mix excessibility.debug test/my_test.exs --analyze=#{name}

    # Run with only default analyzers
    mix excessibility.debug test/my_test.exs

    # Run with all analyzers
    mix excessibility.debug test/my_test.exs --analyze=all
    ```
    """
  end

  defp get_module_doc(analyzer) do
    case Code.fetch_docs(analyzer) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        # Remove ## headings that we'll add ourselves
        doc
        |> String.replace(~r/^## .*$/m, "")
        |> String.trim()

      _ ->
        analyzer_descriptions()[analyzer.name()] ||
          "No documentation available."
    end
  end

  defp get_detects(analyzer) do
    case Code.fetch_docs(analyzer) do
      {:docs_v1, _, :elixir, _, %{"en" => doc}, _, _} ->
        case Regex.run(~r/Detects:\n((?:- .+\n?)+)/m, doc) do
          [_, detects_section] ->
            detects_section
            |> String.split("\n")
            |> Enum.map(&String.replace(&1, ~r/^- /, ""))
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          nil ->
            analyzer_detects()[analyzer.name()] || []
        end

      _ ->
        analyzer_detects()[analyzer.name()] || []
    end
  end

  defp get_fix_info(name) do
    fix_info()[name] ||
      {"Review the analyzer findings and address the identified patterns.", ""}
  end

  defp format_list([]), do: "None"
  defp format_list(items), do: Enum.map_join(items, ", ", &"`#{&1}`")

  defp format_bullet_list([]), do: "- No specific patterns documented"
  defp format_bullet_list(items), do: Enum.map_join(items, "\n", &"- #{&1}")

  defp analyzer_short_descriptions do
    %{
      memory: "Detects memory bloat and leaks using adaptive thresholds",
      performance: "Identifies slow events and bottlenecks",
      data_growth: "Analyzes list growth patterns",
      event_pattern: "Detects inefficient event patterns",
      n_plus_one: "Identifies potential N+1 query issues",
      state_machine: "Analyzes state transitions",
      render_efficiency: "Detects wasted renders with no state changes",
      assign_lifecycle: "Finds dead state (assigns that never change)",
      handle_event_noop: "Detects empty event handlers",
      form_validation: "Flags excessive validation roundtrips",
      summary: "Natural language timeline overview",
      cascade_effect: "Detects rapid event cascades",
      hypothesis: "Root cause suggestions",
      code_pointer: "Maps events to source locations",
      accessibility_correlation: "Flags state changes with a11y implications"
    }
  end

  defp analyzer_descriptions do
    %{
      memory: """
      Analyzes memory usage patterns across timeline events.

      Uses adaptive thresholds based on timeline statistics to avoid
      false positives and work across different test sizes.
      """,
      performance: """
      Analyzes performance patterns across timeline events.

      Uses data from the Duration enricher to identify performance issues
      like slow events and bottlenecks.
      """
    }
  end

  defp analyzer_detects do
    %{
      memory: ["Memory bloat (large growth between events)", "Memory leaks (3+ consecutive increases)"],
      performance: ["Slow events (> mean + 2std_dev)", "Bottlenecks (> 50% of total time)", "Very slow events (> 1000ms)"],
      data_growth: ["Unbounded list growth", "Accumulating data structures"],
      event_pattern: ["Repeated identical events", "Inefficient event sequences"],
      n_plus_one: ["N+1 query patterns", "Repeated database calls in loops"],
      state_machine: ["Invalid state transitions", "Unexpected state sequences"],
      render_efficiency: ["Wasted renders (no state change)", "Unnecessary re-renders"],
      assign_lifecycle: ["Dead assigns (never change after mount)", "Unused state"],
      handle_event_noop: ["Empty event handlers", "No-op event processing"],
      form_validation: ["Excessive validation roundtrips", "Validation loops"],
      cascade_effect: ["Rapid event cascades", "Event chain reactions"],
      hypothesis: ["Root cause patterns", "Correlation between events and issues"],
      code_pointer: ["Source code locations", "Call sites for events"],
      accessibility_correlation: ["State changes affecting ARIA", "A11y-impacting updates"]
    }
  end

  defp fix_info do
    %{
      memory: {
        """
        1. **Use streams for large lists**: Replace `assign(socket, :items, items)` with `stream(socket, :items, items)`
        2. **Limit collection sizes**: Use `Enum.take/2` or sliding window patterns
        3. **Clean up on unmount**: Implement `terminate/2` to release resources
        4. **Avoid keeping history**: Only store what's currently displayed
        """,
        """
        ```elixir
        # Bad: List grows forever
        def handle_info({:new_item, item}, socket) do
          {:noreply, update(socket, :items, &[item | &1])}
        end

        # Good: Use streams with limit
        def handle_info({:new_item, item}, socket) do
          {:noreply, stream_insert(socket, :items, item, limit: 100)}
        end
        ```
        """
      },
      performance: {
        """
        1. **Profile slow events**: Use `:telemetry` or `Excessibility.TelemetryCapture` to identify bottlenecks
        2. **Move expensive work to background**: Use `Task.async` or GenServer for heavy computations
        3. **Cache computed values**: Store results in assigns instead of recomputing
        4. **Optimize queries**: Use indexes, preloads, and query optimization
        """,
        """
        ```elixir
        # Bad: Expensive computation on every event
        def handle_event("search", %{"q" => q}, socket) do
          results = expensive_search(q)  # Blocks the process
          {:noreply, assign(socket, results: results)}
        end

        # Good: Async with loading state
        def handle_event("search", %{"q" => q}, socket) do
          send(self(), {:search, q})
          {:noreply, assign(socket, loading: true)}
        end

        def handle_info({:search, q}, socket) do
          results = expensive_search(q)
          {:noreply, assign(socket, results: results, loading: false)}
        end
        ```
        """
      },
      n_plus_one: {
        """
        1. **Preload associations**: Use `Ecto.Query.preload/3` in your queries
        2. **Use Dataloader**: For conditional/complex loading patterns
        3. **Batch queries**: Load related data in bulk, not per-item
        4. **Cache in assigns**: Load once in mount, not on every render
        """,
        """
        ```elixir
        # Bad: N+1 in template
        <%= for post <- @posts do %>
          <%= post.author.name %>  <!-- Loads author N times -->
        <% end %>

        # Good: Preload in query
        posts = Posts.list_posts() |> Repo.preload(:author)
        ```
        """
      },
      render_efficiency: {
        """
        1. **Check change tracking**: Ensure `assign/3` is not called with unchanged values
        2. **Split components**: Isolate volatile state from stable state
        3. **Use `:if` and `:for`**: Skip rendering unchanged subtrees
        4. **Memoize computations**: Store computed values, don't recompute in template
        """,
        """
        ```elixir
        # Bad: Always assigns, even if unchanged
        def handle_event("tick", _, socket) do
          {:noreply, assign(socket, time: DateTime.utc_now())}
        end

        # Good: Only assign when changed
        def handle_event("tick", _, socket) do
          now = DateTime.utc_now()
          if socket.assigns.time != now do
            {:noreply, assign(socket, time: now)}
          else
            {:noreply, socket}
          end
        end
        ```
        """
      }
    }
  end
end
