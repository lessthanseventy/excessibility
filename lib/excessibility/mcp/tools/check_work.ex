defmodule Excessibility.MCP.Tools.CheckWork do
  @moduledoc """
  Composite MCP tool that runs tests, accessibility checks, and optional
  performance analysis in one call.

  Designed to be called automatically by Claude after modifying code.
  Runs `mix test`, then `mix excessibility`, and optionally
  `mix excessibility.debug` for performance analysis.
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
        "enum" => ["fix_all", "fix_critical", "fix_a11y_only", "show_details", "skip"],
        "enumNames" => [
          "Fix all issues now",
          "Fix critical a11y + perf issues",
          "Fix a11y only",
          "Show full details",
          "Skip"
        ]
      }
    },
    "required" => ["action"]
  }

  @impl true
  def name, do: "check_work"

  @impl true
  def description do
    "Run tests, accessibility checks, and optional performance analysis in one call. " <>
      "Use after modifying code to verify everything still works."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "test_file" => %{
          "type" => "string",
          "description" => "Test file to run (e.g., 'test/my_test.exs' or 'test/my_test.exs:42')"
        },
        "include_perf" => %{
          "type" => "boolean",
          "description" => "Include performance analysis via mix excessibility.debug (default: false)"
        }
      },
      "required" => ["test_file"]
    }
  end

  @impl true
  def execute(%{"test_file" => test_file} = args, opts) when is_binary(test_file) and test_file != "" do
    include_perf? = Map.get(args, "include_perf", false)
    cwd = ClientContext.get_cwd()

    # Step 1: Run tests
    case run_tests(test_file, cwd) do
      {:error, _} = error ->
        error

      :ok ->
        # Step 2: Run a11y check
        a11y_result = run_a11y_check(cwd)

        # Step 3: Optionally run perf analysis
        perf_result =
          if include_perf? do
            run_perf_analysis(test_file, cwd)
          end

        # Step 4: Combine and apply threshold logic
        build_response(a11y_result, perf_result, opts)
    end
  end

  def execute(_args, _opts) do
    {:error, "Missing required argument: test_file"}
  end

  @doc """
  Classifies a list of violations as `:clean`, `:minor`, or `:critical`.

  Critical impacts are "critical" and "serious". If any violation has a critical
  impact, returns `:critical`. If there are only minor/moderate violations,
  returns `:minor`. If there are no violations, returns `:clean`.
  """
  def classify_violations([]), do: :clean

  def classify_violations(violations) do
    has_critical? = Enum.any?(violations, fn v -> v["impact"] in @critical_impacts end)

    if has_critical?, do: :critical, else: :minor
  end

  @doc """
  Builds a human-readable summary from an a11y result and optional perf result.
  """
  def build_summary(a11y_result, perf_result) do
    a11y_section = build_a11y_section(a11y_result)
    perf_section = if perf_result, do: build_perf_section(perf_result)

    sections = [a11y_section | List.wrap(perf_section)]
    Enum.join(sections, "\n\n")
  end

  # Private functions

  defp run_tests(test_file, cwd) do
    {output, exit_code} =
      Subprocess.run("mix", ["test" | String.split(test_file)],
        cd: cwd,
        stderr_to_stdout: true,
        timeout: 120_000
      )

    if exit_code == 0 do
      :ok
    else
      {:error, "Tests failed (exit code #{exit_code}):\n#{output}"}
    end
  end

  defp run_a11y_check(cwd) do
    {output, exit_code} =
      Subprocess.run("mix", ["excessibility"],
        cd: cwd,
        stderr_to_stdout: true,
        timeout: 120_000
      )

    if exit_code == 0 do
      %{"status" => "success", "output" => output}
    else
      %{"status" => "error", "output" => output, "exit_code" => exit_code}
    end
  end

  defp run_perf_analysis(test_file, cwd) do
    {output, exit_code} =
      Subprocess.run("mix", ["excessibility.debug" | String.split(test_file)] ++ ["--format=json"],
        cd: cwd,
        stderr_to_stdout: true,
        timeout: 120_000,
        env: [{"EXCESSIBILITY_TELEMETRY_CAPTURE", "true"}]
      )

    if exit_code == 0 do
      %{"status" => "success", "output" => output}
    else
      %{"status" => "error", "output" => output, "exit_code" => exit_code}
    end
  end

  @doc """
  Extracts a violations list from an a11y result, handling both structured
  and raw output formats.

  - If the result has a `"violations"` key, uses it directly.
  - If it only has `"output"` (raw text), returns `[]` for success or a
    synthetic violation with `"unknown"` impact for non-zero exits.
  """
  def extract_violations(a11y_result) do
    cond do
      is_list(a11y_result["violations"]) ->
        a11y_result["violations"]

      a11y_result["status"] == "success" ->
        []

      a11y_result["status"] == "error" ->
        [%{"id" => "pa11y-error", "impact" => "unknown", "description" => a11y_result["output"]}]

      true ->
        []
    end
  end

  defp build_response(a11y_result, perf_result, opts) do
    violations = extract_violations(a11y_result)
    severity = classify_violations(violations)
    has_perf_concerns? = perf_result != nil and perf_result["status"] == "error"
    summary = build_summary(a11y_result, perf_result)

    case {severity, has_perf_concerns?} do
      {:clean, false} ->
        {:ok, %{"status" => "clean", "message" => "No issues found"}}

      {:minor, false} ->
        {:ok, %{"status" => "minor_issues", "a11y" => a11y_result, "perf" => nil, "summary" => summary}}

      _ ->
        # :critical, or any severity with perf concerns
        maybe_elicit_triage(a11y_result, perf_result, summary, opts)
    end
  end

  defp maybe_elicit_triage(a11y_result, perf_result, summary, opts) do
    elicit = Keyword.get(opts, :elicit)

    if elicit do
      message = "Check work found issues:\n\n#{summary}\n\nHow would you like to proceed?"

      case elicit.(message, @elicitation_schema) do
        {:accept, %{"action" => action}} ->
          {:ok,
           %{
             "status" => "issues_found",
             "action" => action,
             "a11y" => a11y_result,
             "perf" => perf_result,
             "summary" => summary
           }}

        _decline_or_cancel ->
          {:ok,
           %{
             "status" => "issues_found",
             "action" => "skip",
             "a11y" => a11y_result,
             "perf" => perf_result,
             "summary" => summary
           }}
      end
    else
      {:ok,
       %{
         "status" => "issues_found",
         "a11y" => a11y_result,
         "perf" => perf_result,
         "summary" => summary
       }}
    end
  end

  defp build_a11y_section(a11y_result) do
    case a11y_result["status"] do
      "success" ->
        "Accessibility: passed\n#{a11y_result["output"]}"

      "error" ->
        "Accessibility: failed (exit code #{a11y_result["exit_code"]})\n#{a11y_result["output"]}"
    end
  end

  defp build_perf_section(perf_result) do
    case perf_result["status"] do
      "success" ->
        "Performance: passed\n#{perf_result["output"]}"

      "error" ->
        "Performance: failed (exit code #{perf_result["exit_code"]})\n#{perf_result["output"]}"
    end
  end
end
