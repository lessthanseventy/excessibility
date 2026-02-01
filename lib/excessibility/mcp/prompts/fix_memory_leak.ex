defmodule Excessibility.MCP.Prompts.FixMemoryLeak do
  @moduledoc """
  MCP prompt for fixing memory leak patterns in LiveView.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "fix-memory-leak"

  @impl true
  def description, do: "Generate fixes for memory leak patterns in Phoenix LiveView"

  @impl true
  def arguments do
    [
      %{
        "name" => "pattern",
        "description" =>
          "The leak pattern: 'growing_list', 'retained_data', 'binary_accumulation', 'subscription_leak', 'ets_leak'",
        "required" => true
      },
      %{
        "name" => "code_context",
        "description" => "Relevant code snippet showing the leak",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    pattern = Map.get(args, "pattern", "growing_list")
    code_context = Map.get(args, "code_context")

    prompt_text = build_prompt(pattern, code_context)

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

  defp build_prompt(pattern, code_context) do
    """
    # Fixing Memory Leak: #{format_pattern(pattern)}

    #{if code_context, do: "## Your Code\n```elixir\n#{code_context}\n```\n", else: ""}

    #{pattern_specific_fix(pattern)}

    ## Detection

    Use timeline analysis to confirm the leak:

    ```bash
    mix excessibility.debug test/my_test.exs --analyze=memory
    ```

    Look for:
    - **Memory grew Nx between events** - Large jumps
    - **Possible memory leak: consecutive growth** - Steady increase
    - **Unbounded list growth** - Lists never shrinking

    ## Verification

    After applying fixes, run analysis again and verify:
    1. Memory stats show stable or decreasing values
    2. No more "consecutive growth" warnings
    3. Max memory stays within expected bounds

    ## General Principles

    1. **Bound all collections**: Every list should have a maximum size
    2. **Clean up on exit**: Implement `terminate/2` for cleanup
    3. **Avoid retaining references**: Don't store data you don't need
    4. **Use temporary assigns**: For flash/transient data
    5. **Monitor with telemetry**: Add memory tracking in production
    """
  end

  defp format_pattern("growing_list"), do: "Growing List"
  defp format_pattern("retained_data"), do: "Retained Data"
  defp format_pattern("binary_accumulation"), do: "Binary Accumulation"
  defp format_pattern("subscription_leak"), do: "Subscription Leak"
  defp format_pattern("ets_leak"), do: "ETS Table Leak"
  defp format_pattern(pattern), do: pattern

  defp pattern_specific_fix("growing_list") do
    """
    ## Growing List Pattern

    **Problem**: Lists that only grow, never shrink or get cleared.

    ### Common Anti-Patterns

    ```elixir
    # Bad: List grows forever
    def handle_info({:new_message, msg}, socket) do
      {:noreply, update(socket, :messages, &[msg | &1])}
    end

    # Bad: History accumulates
    def handle_event("action", _, socket) do
      {:noreply, update(socket, :history, &[socket.assigns.state | &1])}
    end
    ```

    ### Solutions

    #### 1. Use Streams with Limit

    ```elixir
    def mount(_params, _session, socket) do
      {:ok, stream(socket, :messages, [], limit: 100)}
    end

    def handle_info({:new_message, msg}, socket) do
      {:noreply, stream_insert(socket, :messages, msg, limit: 100)}
    end
    ```

    #### 2. Sliding Window

    ```elixir
    @max_messages 100

    def handle_info({:new_message, msg}, socket) do
      messages =
        [msg | socket.assigns.messages]
        |> Enum.take(@max_messages)

      {:noreply, assign(socket, messages: messages)}
    end
    ```

    #### 3. Periodic Cleanup

    ```elixir
    def mount(_params, _session, socket) do
      if connected?(socket), do: :timer.send_interval(60_000, :cleanup)
      {:ok, assign(socket, messages: [])}
    end

    def handle_info(:cleanup, socket) do
      # Keep only last hour of messages
      cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)
      messages = Enum.filter(socket.assigns.messages, &(DateTime.after?(&1.at, cutoff)))
      {:noreply, assign(socket, messages: messages)}
    end
    ```
    """
  end

  defp pattern_specific_fix("retained_data") do
    """
    ## Retained Data Pattern

    **Problem**: Keeping data in assigns that's no longer needed or displayed.

    ### Common Anti-Patterns

    ```elixir
    # Bad: Keeping all loaded data
    def handle_event("load_details", %{"id" => id}, socket) do
      details = load_details(id)
      {:noreply, assign(socket, details: details)}  # Never cleared
    end

    # Bad: Caching everything
    def handle_info({:data, data}, socket) do
      cache = Map.put(socket.assigns.cache, data.id, data)
      {:noreply, assign(socket, cache: cache)}  # Grows forever
    end
    ```

    ### Solutions

    #### 1. Clear When Not Needed

    ```elixir
    def handle_event("close_details", _, socket) do
      {:noreply, assign(socket, details: nil)}
    end

    def handle_event("navigate", _, socket) do
      # Clear state from previous page
      {:noreply, assign(socket, [
        details: nil,
        search_results: nil,
        preview: nil
      ])}
    end
    ```

    #### 2. Bounded Cache

    ```elixir
    @max_cache_size 50

    def handle_info({:data, data}, socket) do
      cache =
        socket.assigns.cache
        |> Map.put(data.id, data)
        |> limit_cache_size(@max_cache_size)

      {:noreply, assign(socket, cache: cache)}
    end

    defp limit_cache_size(cache, max) when map_size(cache) > max do
      cache
      |> Enum.sort_by(fn {_, v} -> v.accessed_at end)
      |> Enum.take(max)
      |> Map.new()
    end
    defp limit_cache_size(cache, _max), do: cache
    ```

    #### 3. Use Temporary Assigns

    ```elixir
    def mount(_params, _session, socket) do
      {:ok, socket, temporary_assigns: [flash_messages: [], notifications: []]}
    end
    ```
    """
  end

  defp pattern_specific_fix("binary_accumulation") do
    """
    ## Binary Accumulation Pattern

    **Problem**: Storing large binaries (images, files) in assigns.

    ### Common Anti-Patterns

    ```elixir
    # Bad: Storing file content
    def handle_event("upload", %{"file" => file}, socket) do
      content = File.read!(file.path)
      {:noreply, assign(socket, file_content: content)}
    end

    # Bad: Accumulating uploaded files
    def handle_event("upload", entry, socket) do
      files = [entry.client_data | socket.assigns.files]
      {:noreply, assign(socket, files: files)}
    end
    ```

    ### Solutions

    #### 1. Store References, Not Data

    ```elixir
    def handle_event("upload", entry, socket) do
      # Store path/URL, not content
      path = save_to_storage(entry)
      {:noreply, assign(socket, file_path: path)}
    end
    ```

    #### 2. Process and Discard

    ```elixir
    def handle_event("upload", entry, socket) do
      # Process immediately, don't store
      result = process_file(entry)
      {:noreply, assign(socket, result: result)}
      # entry content is garbage collected
    end
    ```

    #### 3. Use LiveView Uploads

    ```elixir
    def mount(_params, _session, socket) do
      {:ok, allow_upload(socket, :file, accept: ~w(.jpg .png), max_entries: 1)}
    end

    def handle_event("save", _, socket) do
      [path] = consume_uploaded_entries(socket, :file, fn %{path: path}, _entry ->
        dest = Path.join("uploads", Path.basename(path))
        File.cp!(path, dest)
        {:ok, dest}
      end)
      {:noreply, assign(socket, uploaded_path: path)}
    end
    ```
    """
  end

  defp pattern_specific_fix("subscription_leak") do
    """
    ## Subscription Leak Pattern

    **Problem**: PubSub subscriptions or process monitors not cleaned up.

    ### Common Anti-Patterns

    ```elixir
    # Bad: Subscribing without tracking
    def handle_event("watch", %{"topic" => topic}, socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, topic)
      {:noreply, socket}  # Never unsubscribes
    end

    # Bad: Multiple subscriptions to same topic
    def handle_params(%{"id" => id}, _uri, socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, "item:\#{id}")
      {:noreply, socket}  # Subscribes every navigation
    end
    ```

    ### Solutions

    #### 1. Track and Unsubscribe

    ```elixir
    def handle_event("watch", %{"topic" => topic}, socket) do
      Phoenix.PubSub.subscribe(MyApp.PubSub, topic)
      {:noreply, assign(socket, subscribed_topics: [topic | socket.assigns.subscribed_topics])}
    end

    def terminate(_reason, socket) do
      for topic <- socket.assigns.subscribed_topics do
        Phoenix.PubSub.unsubscribe(MyApp.PubSub, topic)
      end
      :ok
    end
    ```

    #### 2. Subscribe Once in Mount

    ```elixir
    def mount(_params, _session, socket) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MyApp.PubSub, "global")
      end
      {:ok, socket}
    end
    ```

    #### 3. Unsubscribe Before Resubscribe

    ```elixir
    def handle_params(%{"id" => id}, _uri, socket) do
      topic = "item:\#{id}"
      old_topic = socket.assigns[:current_topic]

      if old_topic && old_topic != topic do
        Phoenix.PubSub.unsubscribe(MyApp.PubSub, old_topic)
      end

      if old_topic != topic do
        Phoenix.PubSub.subscribe(MyApp.PubSub, topic)
      end

      {:noreply, assign(socket, current_topic: topic)}
    end
    ```
    """
  end

  defp pattern_specific_fix("ets_leak") do
    """
    ## ETS Table Leak Pattern

    **Problem**: ETS tables created but never deleted, or entries accumulating.

    ### Common Anti-Patterns

    ```elixir
    # Bad: Creating table per request
    def handle_event("process", _, socket) do
      table = :ets.new(:temp, [:set])
      # ... use table ...
      {:noreply, socket}  # Table never deleted
    end

    # Bad: Entries never cleaned
    def cache_result(key, value) do
      :ets.insert(:cache, {key, value, DateTime.utc_now()})
      # Entries accumulate forever
    end
    ```

    ### Solutions

    #### 1. Delete Tables When Done

    ```elixir
    def handle_event("process", _, socket) do
      table = :ets.new(:temp, [:set])
      try do
        result = do_processing(table)
        {:noreply, assign(socket, result: result)}
      after
        :ets.delete(table)
      end
    end
    ```

    #### 2. Use Named Table with TTL

    ```elixir
    def init_cache do
      :ets.new(:cache, [:named_table, :set, :public])
      :timer.send_interval(60_000, self(), :cleanup_cache)
    end

    def handle_info(:cleanup_cache, state) do
      cutoff = DateTime.add(DateTime.utc_now(), -300, :second)
      :ets.select_delete(:cache, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
      {:noreply, state}
    end
    ```

    #### 3. Use Cachex or Similar

    ```elixir
    # In application.ex
    children = [
      {Cachex, name: :my_cache, limit: 1000, expiration: 300_000}
    ]

    # Usage
    Cachex.put(:my_cache, key, value)
    Cachex.get(:my_cache, key)
    ```
    """
  end

  defp pattern_specific_fix(_) do
    """
    ## General Memory Leak Fix

    1. Run timeline analysis to identify the leak pattern
    2. Check for unbounded collections
    3. Verify cleanup in terminate/2
    4. Use temporary_assigns for transient data
    5. Consider using streams for large lists
    """
  end
end
