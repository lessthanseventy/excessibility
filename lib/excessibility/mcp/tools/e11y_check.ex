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
        }
      }
    }
  end

  @impl true
  def execute(args, opts) do
    test_args = Map.get(args, "test_args", "")
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Starting Pa11y check...", 0)

    {output, exit_code} =
      if test_args == "" do
        System.cmd("mix", ["excessibility"], stderr_to_stdout: true)
      else
        cmd_args = String.split(test_args)
        System.cmd("mix", ["excessibility" | cmd_args], stderr_to_stdout: true)
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
