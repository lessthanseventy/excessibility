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
    "Run tests with telemetry capture. Returns timeline data for performance analysis. " <>
      "NOTE: Tests must call html_snapshot() to generate timeline events. " <>
      "Use generate_test to scaffold proper tests first."
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

    debug_log("e11y_debug.execute starting")

    if progress_callback, do: progress_callback.("Running tests with telemetry capture...", 0)

    cmd_args = String.split(test_args)
    cmd_args = if analyzers, do: cmd_args ++ ["--analyze=#{analyzers}"], else: cmd_args

    cmd_opts = ClientContext.cmd_opts(stderr_to_stdout: true)

    debug_log("e11y_debug: calling subprocess")
    {output, exit_code} = run_with_optional_timeout(cmd_args, cmd_opts, timeout)
    debug_log("e11y_debug: subprocess returned exit_code=#{exit_code} output_len=#{String.length(output)}")

    if progress_callback, do: progress_callback.("Reading timeline...", 80)

    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    timeline_path = ClientContext.client_path(Path.join(base_path, "timeline.json"))
    debug_log("e11y_debug: timeline_path=#{timeline_path}")

    # Write full output to temp file instead of returning it
    output_file = Path.join(System.tmp_dir!(), "e11y_debug_output_#{System.os_time(:second)}.txt")
    File.write!(output_file, output)
    debug_log("e11y_debug: wrote output to #{output_file}")

    timeline =
      if File.exists?(timeline_path) do
        debug_log("e11y_debug: reading timeline file")

        case File.read(timeline_path) do
          {:ok, content} ->
            debug_log("e11y_debug: timeline file read, size=#{byte_size(content)}")
            Jason.decode!(content)

          _ ->
            debug_log("e11y_debug: failed to read timeline")
            nil
        end
      else
        debug_log("e11y_debug: timeline file does not exist")
        nil
      end

    debug_log("e11y_debug: building result")
    if progress_callback, do: progress_callback.("Debug complete", 100)

    # Extract just test result line (e.g. "1 test, 1 failure")
    result_line =
      output
      |> String.split("\n")
      |> Enum.find(fn line -> line =~ ~r/\d+\s+(test|failure|passed)/ end)
      |> Kernel.||("See output_file for details")

    result =
      {:ok,
       %{
         "status" => if(exit_code == 0, do: "success", else: "failure"),
         "exit_code" => exit_code,
         "output_file" => output_file,
         "result_summary" => result_line,
         "timeline_path" => timeline_path,
         "timeline" => timeline
       }}

    debug_log("e11y_debug: returning result")
    result
  end

  defp debug_log(msg) do
    case System.get_env("MCP_LOG_FILE") do
      nil -> :ok
      path -> File.write!(path, "[#{DateTime.utc_now()}] #{msg}\n", [:append])
    end
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
