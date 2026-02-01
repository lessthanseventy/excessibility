defmodule Excessibility.MCP.Tools.E11yDebug do
  @moduledoc """
  MCP tool for running tests with telemetry capture and timeline analysis.
  """

  @behaviour Excessibility.MCP.Tool

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
          "description" => "Arguments to pass to mix test (required)"
        },
        "analyzers" => %{
          "type" => "string",
          "description" => "Comma-separated list of analyzers to run"
        },
        "cwd" => %{
          "type" => "string",
          "description" =>
            "Working directory to run tests from (defaults to current directory). Required when testing projects other than excessibility itself."
        }
      },
      "required" => ["test_args"]
    }
  end

  @impl true
  def execute(args, opts) do
    test_args = Map.get(args, "test_args", "")
    analyzers = Map.get(args, "analyzers")
    cwd = Map.get(args, "cwd")
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Running tests with telemetry capture...", 0)

    cmd_args = String.split(test_args)
    cmd_args = if analyzers, do: cmd_args ++ ["--analyze=#{analyzers}"], else: cmd_args

    cmd_opts = [stderr_to_stdout: true]
    cmd_opts = if cwd && File.dir?(cwd), do: [{:cd, cwd} | cmd_opts], else: cmd_opts

    {output, exit_code} = System.cmd("mix", ["excessibility.debug" | cmd_args], cmd_opts)

    if progress_callback, do: progress_callback.("Reading timeline...", 80)

    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

    timeline_path =
      if cwd && File.dir?(cwd) do
        Path.join([cwd, base_path, "timeline.json"])
      else
        Path.join(base_path, "timeline.json")
      end

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
end
