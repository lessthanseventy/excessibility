defmodule Excessibility.MCP.Progress do
  @moduledoc """
  Helper for sending MCP progress notifications.

  Progress notifications allow tools to report their progress during
  long-running operations.

  ## Usage

      # In a tool's execute function:
      def execute(args, opts) do
        callback = Keyword.get(opts, :progress_callback)

        if callback do
          callback.("Starting...", 0)
          # ... do work ...
          callback.("Processing...", 50)
          # ... more work ...
          callback.("Complete", 100)
        end

        {:ok, result}
      end

      # When calling the tool with progress support:
      callback = Progress.callback(token: "op-123")
      Tool.execute(args, progress_callback: callback)
  """

  @doc """
  Sends a progress notification to stdout.

  This is used internally by the callback function.
  """
  def notify(message, progress, opts \\ []) do
    token = Keyword.get(opts, :token)

    notification = %{
      "jsonrpc" => "2.0",
      "method" => "notifications/progress",
      "params" => %{
        "progressToken" => token,
        "progress" => progress,
        "total" => 100,
        "message" => message
      }
    }

    json = Jason.encode!(notification)
    IO.write(:stdio, json <> "\n")
  end

  @doc """
  Creates a progress callback function.

  The returned function can be passed to tools via the `:progress_callback` option.

  ## Options

  - `:token` - Progress token for correlating notifications (optional)
  - `:io` - IO device to write to (default: :stdio)

  ## Example

      callback = Progress.callback(token: "operation-123")
      callback.("Processing...", 50)
  """
  def callback(opts \\ []) do
    fn message, progress ->
      notify(message, progress, opts)
    end
  end

  @doc """
  Wraps a function with progress notifications.

  Sends start (0%) and complete (100%) notifications automatically.

  ## Example

      result = Progress.with_progress(
        "Running analysis",
        token: "analysis-1",
        fn ->
          expensive_operation()
        end
      )
  """
  def with_progress(description, opts \\ [], fun) do
    notify("Starting: #{description}", 0, opts)

    try do
      result = fun.()
      notify("Complete: #{description}", 100, opts)
      result
    rescue
      e ->
        notify("Failed: #{description}", 100, opts)
        reraise e, __STACKTRACE__
    end
  end
end
