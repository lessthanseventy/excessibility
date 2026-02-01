defmodule Excessibility.MCP.Prompts.OptimizeLiveview do
  @moduledoc """
  MCP prompt for LiveView performance optimization patterns.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "optimize-liveview"

  @impl true
  def description, do: "Generate performance optimization recommendations for Phoenix LiveView"

  @impl true
  def arguments do
    [
      %{
        "name" => "symptom",
        "description" => "The performance symptom: 'slow_render', 'high_memory', 'slow_events', 'laggy_ui', 'slow_mount'",
        "required" => true
      },
      %{
        "name" => "context",
        "description" => "Additional context about the LiveView (e.g., 'large list', 'many components')",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    symptom = Map.get(args, "symptom", "slow_render")
    context = Map.get(args, "context")

    prompt_text = build_prompt(symptom, context)

    {:ok,
     %{
       "messages" => [
         %{
           "role" => "user",
           "content" => %{
             "type" => "text",
             "text" => prompt_text
           }
         }
       ]
     }}
  end

  defp build_prompt(symptom, context) do
    base_prompt = """
    # LiveView Performance Optimization

    ## Symptom: #{format_symptom(symptom)}
    #{if context, do: "## Context: #{context}\n", else: ""}

    #{symptom_specific_guidance(symptom)}

    ## General Performance Patterns

    ### 1. Change Tracking
    LiveView only re-renders changed assigns. Ensure you're leveraging this:

    ```elixir
    # Bad: Always assigns even when unchanged
    def handle_info(:tick, socket) do
      {:noreply, assign(socket, time: DateTime.utc_now())}
    end

    # Good: Only assign when value changed
    def handle_info(:tick, socket) do
      now = DateTime.utc_now()
      if socket.assigns.time != now do
        {:noreply, assign(socket, time: now)}
      else
        {:noreply, socket}
      end
    end
    ```

    ### 2. Streams for Large Collections
    Use streams instead of assigns for lists that change frequently:

    ```elixir
    # Bad: Full list in assigns
    def mount(_params, _session, socket) do
      {:ok, assign(socket, items: fetch_items())}
    end

    # Good: Stream with limit
    def mount(_params, _session, socket) do
      {:ok, stream(socket, :items, fetch_items(), limit: 100)}
    end
    ```

    ### 3. Preload Associations
    Avoid N+1 queries by preloading in mount:

    ```elixir
    # Bad: Loads associations in template
    <%= for post <- @posts do %>
      <%= post.author.name %>  <!-- N queries -->
    <% end %>

    # Good: Preload upfront
    posts = Posts.list() |> Repo.preload(:author)
    ```

    ### 4. Async Operations
    Move expensive work out of the request cycle:

    ```elixir
    # Bad: Blocks on slow operation
    def handle_event("search", %{"q" => q}, socket) do
      results = slow_search(q)
      {:noreply, assign(socket, results: results)}
    end

    # Good: Async with loading state
    def handle_event("search", %{"q" => q}, socket) do
      send(self(), {:search, q})
      {:noreply, assign(socket, loading: true)}
    end

    def handle_info({:search, q}, socket) do
      results = slow_search(q)
      {:noreply, assign(socket, results: results, loading: false)}
    end
    ```

    ### 5. Component Optimization
    Split volatile and stable state:

    ```elixir
    # Stable content in stateless component
    <.static_header />

    # Volatile content isolated
    <.live_component module={TickerComponent} id="ticker" />
    ```

    ## Debugging Tools

    Use `mix excessibility.debug` to capture timeline and analyze:

    ```bash
    # Run test with timeline capture
    mix excessibility.debug test/my_live_test.exs

    # Analyze specific patterns
    mix excessibility.debug test/my_test.exs --analyze=memory,performance
    ```

    Review the timeline.json for event durations and memory patterns.
    """

    base_prompt
  end

  defp format_symptom("slow_render"), do: "Slow Rendering / UI Updates"
  defp format_symptom("high_memory"), do: "High Memory Usage"
  defp format_symptom("slow_events"), do: "Slow Event Handling"
  defp format_symptom("laggy_ui"), do: "Laggy/Unresponsive UI"
  defp format_symptom("slow_mount"), do: "Slow Initial Mount"
  defp format_symptom(symptom), do: symptom

  defp symptom_specific_guidance("slow_render") do
    """
    ## Slow Render Analysis

    Common causes:
    1. **Unnecessary re-renders**: Check if assigns change when they shouldn't
    2. **Large template**: Split into components to localize changes
    3. **Expensive comprehensions**: Pre-compute in handle_* functions
    4. **Many DOM elements**: Use virtualization or pagination

    ### Quick Fixes

    ```elixir
    # Use :if to skip unchanged subtrees
    <div :if={@show_details}>
      <!-- Complex content -->
    </div>

    # Memoize computed values
    socket = assign(socket,
      items: items,
      item_count: length(items),  # Don't compute in template
      formatted_items: format_items(items)
    )
    ```
    """
  end

  defp symptom_specific_guidance("high_memory") do
    """
    ## High Memory Analysis

    Common causes:
    1. **Unbounded lists**: Lists growing without limit
    2. **Retained data**: Keeping data that's no longer displayed
    3. **Large binaries**: Images/files stored in assigns
    4. **Subscription accumulation**: PubSub subscriptions not cleaned up

    ### Quick Fixes

    ```elixir
    # Use streams with limits
    {:ok, stream(socket, :items, items, limit: 50)}

    # Clear old data
    def handle_info(:cleanup, socket) do
      {:noreply, assign(socket, old_data: nil)}
    end

    # Don't store binaries
    # Store URLs/paths instead of actual file content
    ```
    """
  end

  defp symptom_specific_guidance("slow_events") do
    """
    ## Slow Event Handling

    Common causes:
    1. **Blocking operations**: Database/API calls in handle_event
    2. **Complex computations**: Heavy processing in event handlers
    3. **Cascade updates**: One event triggering many others

    ### Quick Fixes

    ```elixir
    # Move slow work to handle_info
    def handle_event("action", params, socket) do
      send(self(), {:do_action, params})
      {:noreply, assign(socket, processing: true)}
    end

    # Batch related updates
    {:noreply, assign(socket, [
      field1: value1,
      field2: value2,
      field3: value3
    ])}
    ```
    """
  end

  defp symptom_specific_guidance("laggy_ui") do
    """
    ## Laggy UI Analysis

    Common causes:
    1. **Debounce missing**: Too many events firing
    2. **Heavy re-renders**: Large DOM updates
    3. **Blocking main loop**: Sync operations blocking the process

    ### Quick Fixes

    ```heex
    <!-- Debounce user input -->
    <input phx-keyup="search" phx-debounce="300" />

    <!-- Throttle frequent events -->
    <div phx-click="action" phx-throttle="500">
    ```

    ```elixir
    # Use temporary assigns for flash data
    def mount(_params, _session, socket) do
      {:ok, socket, temporary_assigns: [flash_items: []]}
    end
    ```
    """
  end

  defp symptom_specific_guidance("slow_mount") do
    """
    ## Slow Mount Analysis

    Common causes:
    1. **Heavy queries**: Loading too much data upfront
    2. **Sync operations**: API calls blocking mount
    3. **Complex setup**: Too much initialization

    ### Quick Fixes

    ```elixir
    # Load minimum data, lazy load rest
    def mount(_params, _session, socket) do
      if connected?(socket) do
        send(self(), :load_full_data)
      end
      {:ok, assign(socket, loading: true, data: nil)}
    end

    def handle_info(:load_full_data, socket) do
      {:noreply, assign(socket, loading: false, data: load_data())}
    end
    ```
    """
  end

  defp symptom_specific_guidance(_) do
    """
    ## General Analysis

    Run timeline analysis to identify specific issues:

    ```bash
    mix excessibility.debug test/my_test.exs --verbose
    ```

    Review the output for memory, performance, and event pattern findings.
    """
  end
end
