defmodule Excessibility.MCP.Tools.E11yDebug do
  @moduledoc """
  MCP tool for running tests with telemetry capture and timeline analysis.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext
  alias Excessibility.MCP.Subprocess

  @impl true
  def name, do: "e11y_debug"

  @impl true
  def description do
    "SLOW: Run tests with telemetry capture and timeline analysis. " <>
      "Use SINGLE test files only (not directories). Always pass timeout: 300000 (5 min)."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_args" => %{
          "type" => "string",
          "description" =>
            "REQUIRED. Path to SINGLE test file (e.g., 'test/my_test.exs'). " <>
              "NEVER use directories - they cause hangs!"
        },
        "analyzers" => %{
          "type" => "string",
          "description" => "Comma-separated analyzers (optional). Default: all enabled."
        },
        "timeout" => %{
          "type" => "integer",
          "description" => "STRONGLY RECOMMENDED: 300000 (5 min). Without timeout, tool may hang indefinitely."
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

  defp run_with_optional_timeout(cmd_args, cmd_opts, timeout) do
    mix_args = ["excessibility.debug" | cmd_args]
    subprocess_opts = build_subprocess_opts(cmd_opts, timeout)
    Subprocess.run("mix", mix_args, subprocess_opts)
  end

  defp build_subprocess_opts(cmd_opts, timeout) do
    opts = []
    opts = if Keyword.get(cmd_opts, :stderr_to_stdout), do: [{:stderr_to_stdout, true} | opts], else: opts
    opts = if cd = Keyword.get(cmd_opts, :cd), do: [{:cd, cd} | opts], else: opts
    opts = if env = Keyword.get(cmd_opts, :env), do: [{:env, env} | opts], else: opts
    opts = if timeout, do: [{:timeout, timeout} | opts], else: opts
    opts
  end
end
