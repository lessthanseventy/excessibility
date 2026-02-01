defmodule Excessibility.MCP.Tools.E11yCheck do
  @moduledoc """
  MCP tool for running Pa11y accessibility checks on HTML snapshots.
  """

  @behaviour Excessibility.MCP.Tool

  @impl true
  def name, do: "e11y_check"

  @impl true
  def description do
    "Run Pa11y accessibility checks on HTML snapshots. Without args: check existing snapshots. With test_args: run tests first, then check."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_args" => %{
          "type" => "string",
          "description" => "Arguments to pass to mix test (optional)"
        },
        "cwd" => %{
          "type" => "string",
          "description" =>
            "Working directory to run tests from (defaults to current directory). Required when testing projects other than excessibility itself."
        }
      }
    }
  end

  @impl true
  def execute(args, opts) do
    test_args = Map.get(args, "test_args", "")
    cwd = Map.get(args, "cwd")
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Starting Pa11y check...", 0)

    cmd_opts = [stderr_to_stdout: true]
    cmd_opts = if cwd && File.dir?(cwd), do: [{:cd, cwd} | cmd_opts], else: cmd_opts

    {output, exit_code} =
      if test_args == "" do
        System.cmd("mix", ["excessibility"], cmd_opts)
      else
        cmd_args = String.split(test_args)
        System.cmd("mix", ["excessibility" | cmd_args], cmd_opts)
      end

    if progress_callback, do: progress_callback.("Pa11y check complete", 100)

    {:ok,
     %{
       "status" => if(exit_code == 0, do: "success", else: "failure"),
       "exit_code" => exit_code,
       "output" => output
     }}
  end
end
