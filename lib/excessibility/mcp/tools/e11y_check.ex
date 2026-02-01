defmodule Excessibility.MCP.Tools.E11yCheck do
  @moduledoc """
  MCP tool for running Pa11y accessibility checks on HTML snapshots.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext
  alias Excessibility.MCP.Subprocess

  @impl true
  def name, do: "e11y_check"

  @impl true
  def description do
    "Run Pa11y on snapshots. FAST without test_args. SLOW with test_args (runs tests first). " <>
      "When using test_args: single files only, pass timeout: 300000."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_args" => %{
          "type" => "string",
          "description" => "Optional. If provided, runs tests first. Use SINGLE test file path only!"
        },
        "timeout" => %{
          "type" => "integer",
          "description" => "REQUIRED when using test_args: 300000 (5 min). Prevents indefinite hangs."
        }
      }
    }
  end

  @impl true
  def execute(args, opts) do
    test_args = Map.get(args, "test_args", "")
    timeout = Map.get(args, "timeout")
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Starting Pa11y check...", 0)

    cmd_opts = ClientContext.cmd_opts(stderr_to_stdout: true)

    {output, exit_code} = run_with_optional_timeout(test_args, cmd_opts, timeout)

    if progress_callback, do: progress_callback.("Pa11y check complete", 100)

    {:ok,
     %{
       "status" => if(exit_code == 0, do: "success", else: "failure"),
       "exit_code" => exit_code,
       "output" => output
     }}
  end

  defp run_with_optional_timeout(test_args, cmd_opts, timeout) do
    mix_args =
      if test_args == "" do
        ["excessibility"]
      else
        ["excessibility" | String.split(test_args)]
      end

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
