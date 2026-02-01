defmodule Excessibility.MCP.Tools.E11yDebug do
  @moduledoc """
  MCP tool for running tests with telemetry capture and timeline analysis.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext

  @impl true
  def name, do: "e11y_debug"

  @impl true
  def description do
    "Run tests with telemetry capture and timeline analysis for debugging LiveView state."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_args" => %{
          "type" => "string",
          "description" =>
            "Arguments to pass to mix test (required). Use a SINGLE test file, not a directory - directories are very slow!"
        },
        "analyzers" => %{
          "type" => "string",
          "description" => "Comma-separated list of analyzers to run"
        },
        "timeout" => %{
          "type" => "integer",
          "description" =>
            "Optional timeout in milliseconds. No timeout by default. Recommended: 300000 (5 min) for CI/automation."
        }
      },
      "required" => ["test_args"]
    }
  end

  @impl true
  def execute(args, opts) do
    test_args = Map.get(args, "test_args", "")
    analyzers = Map.get(args, "analyzers")
    timeout = Map.get(args, "timeout")
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Running tests with telemetry capture...", 0)

    cmd_args = String.split(test_args)
    cmd_args = if analyzers, do: cmd_args ++ ["--analyze=#{analyzers}"], else: cmd_args

    cmd_opts = ClientContext.cmd_opts(stderr_to_stdout: true)

    {output, exit_code} = run_with_optional_timeout(cmd_args, cmd_opts, timeout)

    if progress_callback, do: progress_callback.("Reading timeline...", 80)

    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    timeline_path = ClientContext.client_path(Path.join(base_path, "timeline.json"))

    timeline =
      if File.exists?(timeline_path) do
        case File.read(timeline_path) do
          {:ok, content} -> Jason.decode!(content)
          _ -> nil
        end
      end

    if progress_callback, do: progress_callback.("Debug complete", 100)

    {:ok,
     %{
       "status" => if(exit_code == 0, do: "success", else: "failure"),
       "exit_code" => exit_code,
       "output" => output,
       "timeline_path" => timeline_path,
       "timeline" => timeline
     }}
  end

  defp run_with_optional_timeout(cmd_args, cmd_opts, nil) do
    # No timeout - run directly
    System.cmd("mix", ["excessibility.debug" | cmd_args], cmd_opts)
  end

  defp run_with_optional_timeout(cmd_args, cmd_opts, timeout) when is_integer(timeout) do
    task =
      Task.async(fn ->
        System.cmd("mix", ["excessibility.debug" | cmd_args], cmd_opts)
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {"Error: Test timed out after #{div(timeout, 1000)} seconds", 124}
    end
  end
end
