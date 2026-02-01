defmodule Excessibility.MCP.Tools.SuggestFixes do
  @moduledoc """
  MCP tool for parsing Pa11y output and suggesting Phoenix-specific fixes.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.Subprocess

  @impl true
  def name, do: "suggest_fixes"

  @impl true
  def description do
    "Suggest Phoenix/LiveView fixes for a11y violations. FAST with pa11y_output provided. " <>
      "SLOW if run_pa11y=true. Pass timeout: 300000 when running Pa11y."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "pa11y_output" => %{
          "type" => "string",
          "description" => "Raw Pa11y output or JSON results to parse"
        },
        "run_pa11y" => %{
          "type" => "boolean",
          "description" => "Run Pa11y first and analyze the results (default: false)"
        },
        "timeout" => %{
          "type" => "integer",
          "description" => "REQUIRED when run_pa11y=true: 300000 (5 min). Prevents indefinite hangs."
        }
      }
    }
  end

  @impl true
  def execute(args, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)
    run_pa11y? = Map.get(args, "run_pa11y", false)
    timeout = Map.get(args, "timeout")

    pa11y_output =
      if run_pa11y? do
        if progress_callback, do: progress_callback.("Running Pa11y...", 0)

        subprocess_opts = [stderr_to_stdout: true]
        subprocess_opts = if timeout, do: [{:timeout, timeout} | subprocess_opts], else: subprocess_opts

        {output, _exit_code} = Subprocess.run("mix", ["excessibility"], subprocess_opts)
        output
      else
        Map.get(args, "pa11y_output", "")
      end

    if progress_callback, do: progress_callback.("Parsing issues...", 50)

    issues = parse_pa11y_output(pa11y_output)
    suggestions = Enum.map(issues, &suggest_fix/1)

    if progress_callback, do: progress_callback.("Complete", 100)

    {:ok,
     %{
       "status" => "success",
       "issues_found" => length(issues),
       "suggestions" => suggestions
     }}
  end

  # ============================================================================
  # Parsing
  # ============================================================================

  defp parse_pa11y_output(output) when is_binary(output) do
    case Jason.decode(output) do
      {:ok, data} when is_list(data) ->
        Enum.map(data, &parse_json_issue/1)

      {:ok, %{"issues" => issues}} when is_list(issues) ->
        Enum.map(issues, &parse_json_issue/1)

      _ ->
        parse_text_output(output)
    end
  end

  defp parse_json_issue(%{"code" => code, "message" => message} = issue) do
    %{
      code: code,
      message: message,
      selector: Map.get(issue, "selector"),
      context: Map.get(issue, "context"),
      type: Map.get(issue, "type", "error")
    }
  end

  defp parse_json_issue(issue) when is_map(issue) do
    %{
      code: Map.get(issue, "code") || Map.get(issue, "rule"),
      message: Map.get(issue, "message") || Map.get(issue, "description"),
      selector: Map.get(issue, "selector"),
      context: Map.get(issue, "context") || Map.get(issue, "html"),
      type: Map.get(issue, "type", "error")
    }
  end

  defp parse_text_output(output) do
    output
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["Error:", "Warning:", "Notice:"]))
    |> Enum.map(&parse_text_line/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_text_line(line) do
    cond do
      String.contains?(line, "Error:") -> build_text_issue(line, "error")
      String.contains?(line, "Warning:") -> build_text_issue(line, "warning")
      true -> nil
    end
  end

  defp build_text_issue(line, type) do
    %{type: type, code: extract_code(line), message: extract_message(line), selector: nil, context: nil}
  end

  defp extract_code(line) do
    case Regex.run(~r/\b(WCAG\d+[A-Z]{1,2}\.[^:]+|[A-Z]\d+)\b/, line) do
      [_, code] -> code
      _ -> "unknown"
    end
  end

  defp extract_message(line) do
    line
    |> String.replace(~r/^(Error|Warning|Notice):\s*/, "")
    |> String.trim()
  end

  # ============================================================================
  # Fix Suggestions
  # ============================================================================

  defp suggest_fix(%{code: code, message: message} = issue) do
    suggestion = get_fix_suggestion(code, message)

    %{
      "issue" => %{
        "code" => code,
        "message" => message,
        "type" => Map.get(issue, :type),
        "selector" => Map.get(issue, :selector),
        "context" => Map.get(issue, :context)
      },
      "suggestion" => suggestion
    }
  end

  defp get_fix_suggestion(code, message) do
    rule = identify_rule(code || "", message || "")
    fix_for_rule(rule, code, message)
  end

  defp identify_rule(code, message) do
    Enum.find_value(rule_matchers(), :unknown, fn {rule, matcher} -> if matcher.(code, message), do: rule end)
  end

  # Rule matchers - each returns true if the rule applies
  defp rule_matchers do
    [
      {:h44, &matches_h44?/2},
      {:h37, &matches_h37?/2},
      {:h32, &matches_h32?/2},
      {:h57, &matches_h57?/2},
      {:f65, &matches_f65?/2},
      {:contrast, &matches_contrast?/2}
    ]
  end

  defp matches_h44?(code, message), do: String.contains?(code, "H44") or String.contains?(message, "label")

  defp matches_h37?(code, message),
    do: String.contains?(code, "H37") or (String.contains?(message, "img") and String.contains?(message, "alt"))

  defp matches_h32?(code, message), do: String.contains?(code, "H32") or String.contains?(message, "submit")
  defp matches_h57?(code, message), do: String.contains?(code, "H57") or String.contains?(message, "lang")
  defp matches_f65?(code, message), do: String.contains?(code, "F65") or String.contains?(message, "iframe")
  defp matches_contrast?(_code, message), do: String.contains?(message, "contrast")

  defp fix_for_rule(:h44, _code, _message), do: fix_h44()
  defp fix_for_rule(:h37, _code, _message), do: fix_h37()
  defp fix_for_rule(:h32, _code, _message), do: fix_h32()
  defp fix_for_rule(:h57, _code, _message), do: fix_h57()
  defp fix_for_rule(:f65, _code, _message), do: fix_f65()
  defp fix_for_rule(:contrast, _code, _message), do: fix_contrast()
  defp fix_for_rule(:unknown, code, message), do: fix_unknown(code, message)

  defp fix_h44 do
    %{
      "rule" => "H44",
      "description" => "Form inputs must have associated labels",
      "phoenix_fix" => """
      <!-- Bad: input without label -->
      <input type="text" name="user[name]" id="user_name" />

      <!-- Good: label with for attribute -->
      <label for="user_name">Name</label>
      <input type="text" name="user[name]" id="user_name" />

      <!-- Or using Phoenix form helpers -->
      <.input field={@form[:name]} type="text" label="Name" />
      """,
      "wcag" => "WCAG 2.1 Level A - 1.3.1 Info and Relationships"
    }
  end

  defp fix_h37 do
    %{
      "rule" => "H37",
      "description" => "Images must have alt attributes",
      "phoenix_fix" => """
      <!-- Bad: image without alt -->
      <img src={@avatar_url} />

      <!-- Good: descriptive alt text -->
      <img src={@avatar_url} alt={"Profile photo of \#{@user.name}"} />

      <!-- For decorative images, use empty alt -->
      <img src="/decorative-border.png" alt="" />
      """,
      "wcag" => "WCAG 2.1 Level A - 1.1.1 Non-text Content"
    }
  end

  defp fix_h32 do
    %{
      "rule" => "H32",
      "description" => "Forms must have submit buttons",
      "phoenix_fix" => """
      <!-- LiveView forms with phx-submit are valid -->
      <form phx-submit="save">
        <!-- inputs -->
        <button type="submit">Save</button>
      </form>

      <!-- If Pa11y still flags this, add to pa11y.json ignore list:
      {
        "ignore": ["WCAG2AA.Principle1.Guideline1_3.1_3_1.H32.2"]
      }
      -->
      """,
      "wcag" => "WCAG 2.1 Level A - 1.3.1 Info and Relationships"
    }
  end

  defp fix_h57 do
    %{
      "rule" => "H57",
      "description" => "HTML element must have lang attribute",
      "phoenix_fix" => """
      <!-- In root.html.heex -->
      <!DOCTYPE html>
      <html lang="en">
        <head>...</head>
        <body>...</body>
      </html>

      <!-- For dynamic language -->
      <html lang={@locale}>
      """,
      "wcag" => "WCAG 2.1 Level A - 3.1.1 Language of Page"
    }
  end

  defp fix_f65 do
    %{
      "rule" => "F65",
      "description" => "Iframes must have title attributes",
      "phoenix_fix" => """
      <!-- Bad -->
      <iframe src={@embed_url}></iframe>

      <!-- Good -->
      <iframe src={@embed_url} title="Embedded video player"></iframe>
      """,
      "wcag" => "WCAG 2.1 Level A - 2.4.1 Bypass Blocks"
    }
  end

  defp fix_contrast do
    %{
      "rule" => "Color Contrast",
      "description" => "Text must have sufficient contrast with background",
      "phoenix_fix" => """
      /* Ensure 4.5:1 ratio for normal text, 3:1 for large text */

      /* Bad: low contrast */
      .text-gray { color: #999; background: #fff; }

      /* Good: sufficient contrast */
      .text-gray { color: #595959; background: #fff; }

      /* Use tools like WebAIM Contrast Checker */
      """,
      "wcag" => "WCAG 2.1 Level AA - 1.4.3 Contrast (Minimum)"
    }
  end

  defp fix_unknown(code, message) do
    %{
      "rule" => code || "unknown",
      "description" => message,
      "phoenix_fix" =>
        "Review the WCAG guidelines for this specific issue. " <>
          "Check https://www.w3.org/WAI/WCAG21/quickref/ for detailed guidance.",
      "wcag" => "See WCAG 2.1 guidelines"
    }
  end
end
