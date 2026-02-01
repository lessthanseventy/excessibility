defmodule Excessibility.MCP.Tools.ListViolations do
  @moduledoc """
  MCP tool for listing structured accessibility violations from Pa11y output.

  Parses Pa11y JSON output into structured violations with summary statistics.
  """

  @behaviour Excessibility.MCP.Tool

  @impl true
  def name, do: "list_violations"

  @impl true
  def description do
    "Parse Pa11y results into structured accessibility violations with summary. " <>
      "Returns violations grouped by rule with fix hints."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "description" => "Path to Pa11y JSON output file (optional, defaults to last run)"
        },
        "run_pa11y" => %{
          "type" => "boolean",
          "description" => "Run Pa11y first and parse the results (default: false)"
        }
      }
    }
  end

  @impl true
  def execute(args, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    run_pa11y? = Map.get(args, "run_pa11y", false)

    output =
      if run_pa11y? do
        if progress_callback, do: progress_callback.("Running Pa11y...", 0)
        {output, _exit_code} = System.cmd("mix", ["excessibility", "--json"], stderr_to_stdout: true)
        output
      else
        load_pa11y_output(args)
      end

    if progress_callback, do: progress_callback.("Parsing violations...", 50)

    violations = parse_violations(output)
    summary = build_summary(violations)

    if progress_callback, do: progress_callback.("Complete", 100)

    {:ok,
     %{
       "violations" => violations,
       "summary" => summary
     }}
  end

  defp load_pa11y_output(%{"path" => path}) when is_binary(path) do
    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp load_pa11y_output(_args) do
    # Try to find most recent Pa11y output
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    pa11y_output_path = Path.join(base_path, "pa11y_results.json")

    case File.read(pa11y_output_path) do
      {:ok, content} -> content
      {:error, _} -> ""
    end
  end

  defp parse_violations(""), do: []

  defp parse_violations(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, data} when is_list(data) ->
        Enum.map(data, &parse_issue/1)

      {:ok, %{"issues" => issues}} when is_list(issues) ->
        Enum.map(issues, &parse_issue/1)

      {:ok, %{"results" => results}} when is_map(results) ->
        # Handle format: %{"results" => %{"file.html" => [issues]}}
        parse_results_format(results)

      {:ok, _} ->
        []

      {:error, %Jason.DecodeError{}} ->
        # Try parsing as text output
        parse_text_violations(output)
    end
  end

  defp parse_results_format(results) do
    results
    |> Enum.flat_map(fn {file, issues} ->
      Enum.map(issues, fn issue -> Map.put(issue, "file", file) end)
    end)
    |> Enum.map(&parse_issue/1)
  end

  defp parse_issue(issue) when is_map(issue) do
    code = Map.get(issue, "code") || Map.get(issue, "rule") || "unknown"
    rule = extract_rule(code)

    %{
      "code" => code,
      "type" => Map.get(issue, "type", "error"),
      "message" => Map.get(issue, "message") || Map.get(issue, "description") || "",
      "selector" => Map.get(issue, "selector"),
      "context" => Map.get(issue, "context") || Map.get(issue, "html"),
      "file" => Map.get(issue, "file"),
      "rule" => rule,
      "fix_hint" => get_fix_hint(rule)
    }
  end

  defp parse_text_violations(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["Error:", "Warning:", "Notice:"]))
    |> Enum.map(&parse_text_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_text_line(line) do
    type =
      cond do
        String.contains?(line, "Error:") -> "error"
        String.contains?(line, "Warning:") -> "warning"
        String.contains?(line, "Notice:") -> "notice"
        true -> nil
      end

    if type do
      code = extract_code_from_text(line)
      rule = extract_rule(code)

      %{
        "code" => code,
        "type" => type,
        "message" => extract_message(line),
        "selector" => nil,
        "context" => nil,
        "file" => nil,
        "rule" => rule,
        "fix_hint" => get_fix_hint(rule)
      }
    end
  end

  defp extract_code_from_text(line) do
    case Regex.run(~r/\b(WCAG\d+[A-Z]{1,2}\.[^\s:]+|[A-Z]\d+)\b/, line) do
      [_, code] -> code
      _ -> "unknown"
    end
  end

  defp extract_message(line) do
    line
    |> String.replace(~r/^(Error|Warning|Notice):\s*/, "")
    |> String.trim()
  end

  @known_rules ~w(H37 H44 H32 H57 H36 H67 F65 F40)

  defp extract_rule(code) when is_binary(code) do
    Enum.find(@known_rules, fn rule -> String.contains?(code, rule) end) ||
      extract_contrast_rule(code) ||
      code
  end

  defp extract_rule(_), do: "unknown"

  defp extract_contrast_rule(code) do
    if String.contains?(code, "contrast") or String.contains?(code, "Contrast") do
      "contrast"
    end
  end

  defp get_fix_hint("H37"), do: "Add alt attribute to image"
  defp get_fix_hint("H44"), do: "Add label element with for attribute matching input id"
  defp get_fix_hint("H32"), do: "Add submit button to form (or use phx-submit)"
  defp get_fix_hint("H57"), do: "Add lang attribute to html element"
  defp get_fix_hint("H36"), do: "Add alt attribute to image used as submit button"
  defp get_fix_hint("H67"), do: "Add empty alt for decorative images"
  defp get_fix_hint("F65"), do: "Add title attribute to iframe"
  defp get_fix_hint("F40"), do: "Remove meta refresh/redirect"
  defp get_fix_hint("contrast"), do: "Increase color contrast ratio (4.5:1 for text)"
  defp get_fix_hint(_), do: nil

  defp build_summary(violations) do
    by_type = Enum.group_by(violations, & &1["type"])
    by_rule = Enum.group_by(violations, & &1["rule"])

    %{
      "total" => length(violations),
      "errors" => length(Map.get(by_type, "error", [])),
      "warnings" => length(Map.get(by_type, "warning", [])),
      "notices" => length(Map.get(by_type, "notice", [])),
      "by_rule" => Map.new(by_rule, fn {rule, issues} -> {rule, length(issues)} end)
    }
  end
end
