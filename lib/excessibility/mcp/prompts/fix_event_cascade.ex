defmodule Excessibility.MCP.Prompts.FixEventCascade do
  @moduledoc """
  MCP prompt for fixing event cascade patterns in LiveView.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "fix-event-cascade"

  @impl true
  def description, do: "Generate fixes for event cascade and loop patterns in Phoenix LiveView"

  @impl true
  def arguments do
    [
      %{
        "name" => "events",
        "description" => "Comma-separated list of events involved in the cascade",
        "required" => false
      },
      %{
        "name" => "cascade_type",
        "description" => "Type of cascade: 'chain_reaction', 'infinite_loop', 'rapid_fire', 'mutual_trigger'",
        "required" => false
      },
      %{
        "name" => "code_context",
        "description" => "Relevant code snippet showing the cascade",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    events = Map.get(args, "events")
    cascade_type = Map.get(args, "cascade_type", "chain_reaction")
    code_context = Map.get(args, "code_context")

    prompt_text = build_prompt(events, cascade_type, code_context)

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

  defp build_prompt(events, cascade_type, code_context) do
    """
    # Fixing Event Cascade: #{format_cascade_type(cascade_type)}

    #{if events, do: "## Events Involved: #{events}\n", else: ""}
    #{if code_context, do: "## Your Code\n```elixir\n#{code_context}\n```\n", else: ""}

    #{cascade_type_specific_fix(cascade_type)}

    ## Detection

    Use timeline analysis to identify cascades:

    ```bash
    mix excessibility.debug test/my_test.exs --analyze=cascade_effect,event_pattern
    ```

    Look for:
    - **Rapid event cascades** - Many events in quick succession
    - **Event chain reaction** - One event triggering multiple others
    - **Repeated identical events** - Same event firing multiple times

    ## General Principles

    1. **Batch related updates**: Use single `assign/3` with keyword list
    2. **Debounce user input**: Use `phx-debounce` on inputs
    3. **Guard against loops**: Add conditions before triggering events
    4. **Consolidate handlers**: Combine related handlers into one
    5. **Avoid cascading sends**: Don't use `send/2` from handle_info

    ## Verification

    After applying fixes:
    1. Check timeline for reduced event count
    2. Verify no more cascade warnings
    3. Test UI responsiveness
    """
  end

  defp format_cascade_type("chain_reaction"), do: "Chain Reaction"
  defp format_cascade_type("infinite_loop"), do: "Infinite Loop"
  defp format_cascade_type("rapid_fire"), do: "Rapid Fire Events"
  defp format_cascade_type("mutual_trigger"), do: "Mutual Trigger"
  defp format_cascade_type(type), do: type

  defp cascade_type_specific_fix("chain_reaction") do
    """
    ## Chain Reaction Pattern

    **Problem**: One event triggers another, which triggers another, creating a chain.

    ### Common Anti-Pattern

    ```elixir
    # Bad: Chain of events
    def handle_event("update_quantity", %{"qty" => qty}, socket) do
      send(self(), :recalculate_subtotal)
      {:noreply, assign(socket, quantity: String.to_integer(qty))}
    end

    def handle_info(:recalculate_subtotal, socket) do
      subtotal = calculate_subtotal(socket.assigns)
      send(self(), :recalculate_total)
      {:noreply, assign(socket, subtotal: subtotal)}
    end

    def handle_info(:recalculate_total, socket) do
      total = calculate_total(socket.assigns)
      send(self(), :update_shipping)
      {:noreply, assign(socket, total: total)}
    end
    # ... chain continues
    ```

    ### Solutions

    #### 1. Batch All Updates Together

    ```elixir
    def handle_event("update_quantity", %{"qty" => qty}, socket) do
      qty = String.to_integer(qty)

      # Calculate everything at once
      subtotal = calculate_subtotal(qty, socket.assigns)
      shipping = calculate_shipping(subtotal, socket.assigns)
      total = subtotal + shipping

      # Single assign with all updates
      {:noreply, assign(socket, [
        quantity: qty,
        subtotal: subtotal,
        shipping: shipping,
        total: total
      ])}
    end
    ```

    #### 2. Use Derived/Computed Values

    ```elixir
    # Only store the source data
    def handle_event("update_quantity", %{"qty" => qty}, socket) do
      {:noreply, assign(socket, quantity: String.to_integer(qty))}
    end

    # Compute derived values in template or component
    # Or use a single compute function
    defp compute_totals(socket) do
      qty = socket.assigns.quantity
      price = socket.assigns.price

      subtotal = qty * price
      shipping = if subtotal > 50, do: 0, else: 5
      total = subtotal + shipping

      assign(socket, subtotal: subtotal, shipping: shipping, total: total)
    end
    ```

    #### 3. Use a Single Recalculation Function

    ```elixir
    def handle_event("update_quantity", params, socket) do
      socket
      |> apply_quantity_change(params)
      |> recalculate_all()
      |> then(&{:noreply, &1})
    end

    defp recalculate_all(socket) do
      # All calculations in one place
      assigns = socket.assigns

      assign(socket, [
        subtotal: assigns.quantity * assigns.price,
        tax: calculate_tax(assigns),
        shipping: calculate_shipping(assigns),
        total: calculate_total(assigns)
      ])
    end
    ```
    """
  end

  defp cascade_type_specific_fix("infinite_loop") do
    """
    ## Infinite Loop Pattern

    **Problem**: Events trigger each other indefinitely.

    ### Common Anti-Pattern

    ```elixir
    # Bad: A triggers B, B triggers A
    def handle_event("update_a", %{"value" => v}, socket) do
      new_b = calculate_b(v)
      send(self(), {:update_b, new_b})
      {:noreply, assign(socket, a: v)}
    end

    def handle_info({:update_b, v}, socket) do
      new_a = calculate_a(v)
      send(self(), {:update_a, new_a})  # Loops back!
      {:noreply, assign(socket, b: v)}
    end
    ```

    ### Solutions

    #### 1. Add Guard Conditions

    ```elixir
    def handle_info({:update_b, v}, socket) do
      # Only trigger if value actually changed
      if socket.assigns.b != v do
        new_a = calculate_a(v)
        # Still don't trigger - let user action drive updates
        {:noreply, assign(socket, b: v, a: new_a)}
      else
        {:noreply, socket}
      end
    end
    ```

    #### 2. Use Source-of-Truth Pattern

    ```elixir
    # Designate one value as source of truth
    def handle_event("update_a", %{"value" => v}, socket) do
      # A is the source, B is derived
      new_b = calculate_b(v)
      {:noreply, assign(socket, a: v, b: new_b)}
    end

    # B updates should be blocked or converted to A updates
    def handle_event("update_b", %{"value" => v}, socket) do
      # Convert to source value
      new_a = reverse_calculate_a(v)
      new_b = calculate_b(new_a)
      {:noreply, assign(socket, a: new_a, b: new_b)}
    end
    ```

    #### 3. Break the Cycle with Flag

    ```elixir
    def handle_event("update_a", %{"value" => v}, socket) do
      new_b = calculate_b(v)
      {:noreply, assign(socket, a: v, b: new_b, updating_from: :a)}
    end

    def handle_info({:update_b, v}, socket) do
      if socket.assigns.updating_from == :a do
        # Skip - this was triggered by A update
        {:noreply, assign(socket, updating_from: nil)}
      else
        {:noreply, assign(socket, b: v)}
      end
    end
    ```
    """
  end

  defp cascade_type_specific_fix("rapid_fire") do
    """
    ## Rapid Fire Events Pattern

    **Problem**: Same event fires many times in quick succession.

    ### Common Anti-Pattern

    ```elixir
    # Bad: No debounce on frequent events
    <input phx-keyup="search" />  <!-- Fires on every keystroke -->

    # Bad: Scroll/resize without throttle
    <div phx-hook="Scroll" phx-scroll="handle_scroll" />
    ```

    ### Solutions

    #### 1. Debounce User Input

    ```heex
    <!-- Wait for user to stop typing -->
    <input phx-keyup="search" phx-debounce="300" />

    <!-- Or use blur for final value -->
    <input phx-blur="update_field" />
    ```

    #### 2. Throttle Frequent Events

    ```heex
    <!-- Limit to once per 500ms -->
    <button phx-click="action" phx-throttle="500">Click</button>
    ```

    #### 3. Client-Side Debounce Hook

    ```javascript
    Hooks.DebouncedInput = {
      mounted() {
        let timeout;
        this.el.addEventListener("input", (e) => {
          clearTimeout(timeout);
          timeout = setTimeout(() => {
            this.pushEvent("search", {value: e.target.value});
          }, 300);
        });
      }
    };
    ```

    #### 4. Server-Side Deduplication

    ```elixir
    def handle_event("search", %{"value" => query}, socket) do
      # Ignore if same as pending search
      if socket.assigns.pending_search == query do
        {:noreply, socket}
      else
        # Cancel previous timer
        if socket.assigns.search_timer do
          Process.cancel_timer(socket.assigns.search_timer)
        end

        # Schedule search
        timer = Process.send_after(self(), {:do_search, query}, 300)
        {:noreply, assign(socket, pending_search: query, search_timer: timer)}
      end
    end
    ```
    """
  end

  defp cascade_type_specific_fix("mutual_trigger") do
    """
    ## Mutual Trigger Pattern

    **Problem**: Two components or handlers trigger each other.

    ### Common Anti-Pattern

    ```elixir
    # Parent triggers child update
    def handle_event("parent_change", _, socket) do
      send_update(ChildComponent, id: "child", data: new_data)
      {:noreply, socket}
    end

    # Child triggers parent update
    # In ChildComponent:
    def handle_event("child_change", _, socket) do
      send(socket.assigns.parent_pid, :refresh)  # Triggers parent!
      {:noreply, socket}
    end
    ```

    ### Solutions

    #### 1. Unidirectional Data Flow

    ```elixir
    # Parent owns state, child only displays
    # Parent
    def render(assigns) do
      ~H\"\"\"
      <.live_component module={Child} id="child" data={@data} />
      \"\"\"
    end

    # Child notifies parent without expecting response
    def handle_event("action", _, socket) do
      send(socket.assigns.parent_pid, {:child_action, result})
      {:noreply, socket}  # Don't wait for update
    end

    # Parent decides if/when to update
    def handle_info({:child_action, result}, socket) do
      if should_update?(result) do
        {:noreply, assign(socket, data: new_data)}
      else
        {:noreply, socket}
      end
    end
    ```

    #### 2. Use Parent as Single Source of Truth

    ```elixir
    # All state lives in parent
    def render(assigns) do
      ~H\"\"\"
      <.live_component
        module={Child}
        id="child"
        value={@value}
        on_change={fn v -> send(self(), {:update_value, v}) end}
      />
      \"\"\"
    end

    # Parent handles all changes
    def handle_info({:update_value, v}, socket) do
      # Single place for all logic
      {:noreply, assign(socket, value: v)}
    end
    ```

    #### 3. Event Bus with Single Handler

    ```elixir
    # Use PubSub for decoupled communication
    def mount(_params, _session, socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, "updates")
      {:ok, socket}
    end

    # One handler decides what to do
    def handle_info({:update, source, data}, socket) do
      case source do
        :parent -> handle_parent_update(data, socket)
        :child -> handle_child_update(data, socket)
      end
    end
    ```
    """
  end

  defp cascade_type_specific_fix(_) do
    """
    ## General Cascade Fix

    1. Identify the event chain using timeline analysis
    2. Find where events trigger other events
    3. Consolidate related handlers
    4. Add guards to prevent re-triggering
    5. Use debounce/throttle for user input
    """
  end
end
