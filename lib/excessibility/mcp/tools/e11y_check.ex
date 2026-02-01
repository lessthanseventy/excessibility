defmodule Excessibility.MCP.Tools.E11yCheck do
  @moduledoc """
  MCP tool for running Pa11y accessibility checks on HTML snapshots.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext

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
          "description" => "Arguments to pass to mix test (optional). Use a single test file, not a directory."
        },
        "timeout" => %{
          "type" => "integer",
          "description" =>
            "Optional timeout in milliseconds. No timeout by default. Recommended: 300000 (5 min) for CI/automation."
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

  defp run_with_optional_timeout(test_args, cmd_opts, nil) do
    # No timeout - run directly
    if test_args == "" do
      System.cmd("mix", ["excessibility"], cmd_opts)
    else
      cmd_args = String.split(test_args)
      System.cmd("mix", ["excessibility" | cmd_args], cmd_opts)
    end
  end

  defp run_with_optional_timeout(test_args, cmd_opts, timeout) when is_integer(timeout) do
    task =
      Task.async(fn ->
        if test_args == "" do
          System.cmd("mix", ["excessibility"], cmd_opts)
        else
          cmd_args = String.split(test_args)
          System.cmd("mix", ["excessibility" | cmd_args], cmd_opts)
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {"Error: Command timed out after #{div(timeout, 1000)} seconds", 124}
    end
  end
end
