defmodule Excessibility.MCP.Tools.A11yCheck do
  @moduledoc """
  MCP tool for running accessibility checks.

  Supports three modes:
  - With `url`: runs axe-core directly against the URL via AxeRunner
  - With `test_args`: runs tests then checks snapshots via `mix excessibility`
  - No args: checks existing snapshots via `mix excessibility`
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.{ClientContext, Subprocess}

  @impl true
  def name, do: "a11y_check"

  @impl true
  def description do
    "Run accessibility checks. Provide a URL for direct checking, " <>
      "or test_args to run tests first, or no args to check existing snapshots."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "url" => %{
          "type" => "string",
          "description" => "URL to check directly (http://, https://, or file://)"
        },
        "test_args" => %{
          "type" => "string",
          "description" => "Arguments to pass to mix test before checking snapshots (e.g., 'test/my_test.exs:42')"
        }
      }
    }
  end

  @impl true
  def execute(%{"url" => url}, _opts) when is_binary(url) and url != "" do
    check_url(url)
  end

  def execute(args, _opts) do
    test_args = Map.get(args, "test_args", "")
    run_mix_excessibility(test_args)
  end

  defp check_url(url) do
    case Excessibility.AxeRunner.run(url) do
      {:ok, result} ->
        violation_count = length(result.violations)

        {:ok,
         %{
           "status" => "success",
           "url" => url,
           "violation_count" => violation_count,
           "violations" => result.violations,
           "passes" => length(result.passes),
           "incomplete" => length(result.incomplete)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_mix_excessibility(test_args) do
    args =
      if test_args == "" do
        ["excessibility"]
      else
        ["excessibility" | String.split(test_args)]
      end

    cwd = ClientContext.get_cwd()

    {output, exit_code} =
      Subprocess.run("mix", args,
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
end
