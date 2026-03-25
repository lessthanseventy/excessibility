defmodule Excessibility.MCP.Tools.A11yCheck do
  @moduledoc """
  MCP tool for running accessibility checks.

  Supports three modes:
  - With `url`: runs axe-core directly against the URL via AxeRunner
  - With `test_args`: runs tests then checks snapshots via `mix excessibility`
  - No args: checks existing snapshots via `mix excessibility`
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext
  alias Excessibility.MCP.Subprocess

  @critical_impacts ["critical", "serious"]

  @elicitation_schema %{
    "type" => "object",
    "properties" => %{
      "action" => %{
        "type" => "string",
        "enum" => ["fix_all", "fix_critical", "show_details", "skip"],
        "enumNames" => [
          "Fix all violations now",
          "Fix critical only",
          "Show full details",
          "Skip"
        ]
      }
    },
    "required" => ["action"]
  }

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
  def execute(%{"url" => url}, opts) when is_binary(url) and url != "" do
    case check_url(url) do
      {:ok, data} ->
        elicit = Keyword.get(opts, :elicit)
        {:ok, maybe_elicit(data, elicit)}

      error ->
        error
    end
  end

  # Elicitation is not available for the mix task path because it returns
  # raw text output, not structured violation data with impact levels.
  # Threshold-based elicitation requires structured violations to classify severity.
  def execute(args, _opts) do
    test_args = Map.get(args, "test_args", "")
    run_mix_excessibility(test_args)
  end

  @doc """
  Applies threshold-based elicitation to accessibility check results.

  When critical/serious violations are found and an elicit callback is available,
  prompts the user to choose how to handle them. Returns data unchanged when
  no elicitation is needed.
  """
  def maybe_elicit(data, elicit) do
    violations = Map.get(data, "violations", [])
    {critical, minor} = Enum.split_with(violations, fn v -> v["impact"] in @critical_impacts end)

    do_elicit(data, violations, critical, minor, elicit)
  end

  defp do_elicit(data, [], _critical, _minor, _elicit), do: data
  defp do_elicit(data, _violations, [], _minor, _elicit), do: data
  defp do_elicit(data, _violations, _critical, _minor, nil), do: data

  defp do_elicit(data, violations, critical, minor, elicit) do
    message = build_elicitation_message(critical, minor)
    apply_elicitation_choice(elicit.(message, @elicitation_schema), data, violations, critical)
  end

  defp apply_elicitation_choice({:accept, %{"action" => "fix_all"}}, data, _violations, _critical), do: data

  defp apply_elicitation_choice({:accept, %{"action" => "fix_critical"}}, data, _violations, critical),
    do: %{data | "violations" => critical, "violation_count" => length(critical)}

  defp apply_elicitation_choice({:accept, %{"action" => "show_details"}}, data, _violations, _critical), do: data

  defp apply_elicitation_choice(_skip_or_decline, _data, violations, _critical),
    do: %{"skipped" => true, "violation_count" => length(violations)}

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

  defp build_elicitation_message(critical, minor) do
    critical_summary =
      Enum.map_join(critical, "\n", &"- #{&1["id"]}: #{length(Map.get(&1, "nodes", []))} element(s)")

    """
    Found #{length(critical)} critical/serious and #{length(minor)} minor accessibility violations.

    Critical:
    #{critical_summary}
    """
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
