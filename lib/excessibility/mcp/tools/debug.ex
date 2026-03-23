defmodule Excessibility.MCP.Tools.Debug do
  @moduledoc """
  MCP tool for running debug analysis on LiveView tests.

  Wraps `mix excessibility.debug` with support for analyzer selection
  and output format.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext
  alias Excessibility.MCP.Subprocess

  @impl true
  def name, do: "debug"

  @impl true
  def description do
    "Run LiveView debug analysis. Captures timeline data showing state evolution, " <>
      "memory usage, and pattern analysis for a test."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_args" => %{
          "type" => "string",
          "description" => "Test arguments passed to mix excessibility.debug (e.g., 'test/my_test.exs:42')"
        },
        "analyzers" => %{
          "type" => "string",
          "description" => "Comma-separated analyzer names (e.g., 'memory,performance,hypothesis')"
        },
        "format" => %{
          "type" => "string",
          "enum" => ["markdown", "json"],
          "description" => "Output format (default: markdown)"
        }
      },
      "required" => ["test_args"]
    }
  end

  @impl true
  def execute(%{"test_args" => test_args} = args, _opts) when is_binary(test_args) and test_args != "" do
    analyzers = Map.get(args, "analyzers")
    format = Map.get(args, "format")

    cmd_args = build_args(test_args, analyzers, format)
    cwd = ClientContext.get_cwd()

    {output, exit_code} =
      Subprocess.run("mix", cmd_args,
        cd: cwd,
        stderr_to_stdout: true,
        timeout: 120_000
      )

    if exit_code == 0 do
      {:ok,
       %{
         "status" => "success",
         "output" => output
       }}
    else
      {:ok,
       %{
         "status" => "error",
         "exit_code" => exit_code,
         "output" => output
       }}
    end
  end

  def execute(_args, _opts) do
    {:error, "Missing required argument: test_args"}
  end

  defp build_args(test_args, analyzers, format) do
    args = ["excessibility.debug" | String.split(test_args)]
    args = if analyzers, do: args ++ ["--analyze=#{analyzers}"], else: args
    args = if format, do: args ++ ["--format=#{format}"], else: args
    args
  end
end
