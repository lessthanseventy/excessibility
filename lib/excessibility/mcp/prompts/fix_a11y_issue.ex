defmodule Excessibility.MCP.Prompts.FixA11yIssue do
  @moduledoc """
  MCP prompt for generating accessibility fix suggestions.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "fix-a11y-issue"

  @impl true
  def description, do: "Generate a prompt for fixing WCAG accessibility violations in Phoenix/LiveView"

  @impl true
  def arguments do
    [
      %{
        "name" => "issue",
        "description" =>
          "The accessibility issue code or description (e.g., 'missing form label', 'WCAG2AA.Principle1.Guideline1_1.1_1_1.H37')",
        "required" => true
      },
      %{
        "name" => "element",
        "description" => "The HTML element or code snippet causing the issue",
        "required" => false
      },
      %{
        "name" => "context",
        "description" => "Additional context like component name or file path",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    issue = Map.get(args, "issue", "unknown accessibility issue")
    element = Map.get(args, "element")
    context = Map.get(args, "context")

    prompt_text = build_prompt(issue, element, context)

    {:ok,
     %{
       "messages" => [
         %{
           "role" => "user",
           "content" => %{
             "type" => "text",
             "text" => prompt_text
           }
         }
       ]
     }}
  end

  defp build_prompt(issue, element, context) do
    base = """
    Fix this accessibility issue in a Phoenix/LiveView application:

    ## Issue
    #{issue}
    """

    base =
      if element do
        base <>
          """

          ## Element
          ```html
          #{element}
          ```
          """
      else
        base
      end

    base =
      if context do
        base <>
          """

          ## Context
          #{context}
          """
      else
        base
      end

    base <>
      """

      ## Requirements
      - Provide the corrected Phoenix/LiveView code (HEEx template syntax)
      - Explain why the original code failed WCAG guidelines
      - Follow Phoenix and LiveView best practices
      - Use semantic HTML elements where appropriate
      - Include any necessary ARIA attributes

      ## Common WCAG Fixes Reference
      - H44: Use `<label>` with `for` attribute matching input `id`
      - H37: Add `alt` attribute to `<img>` elements
      - H32: Ensure forms have submit buttons (or use `phx-submit`)
      - H57: Specify `lang` attribute on `<html>` element
      - F40: Don't use `meta` refresh/redirect
      - F65: Missing `title` attribute on iframes

      Please provide the fixed code and explanation.
      """
  end
end
