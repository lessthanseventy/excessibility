defmodule Excessibility.MCP.Prompts.DebugLiveview do
  @moduledoc """
  MCP prompt for debugging LiveView state and behavior issues.
  """

  @behaviour Excessibility.MCP.Prompt

  @impl true
  def name, do: "debug-liveview"

  @impl true
  def description, do: "Generate a prompt for debugging LiveView state evolution and behavior issues"

  @impl true
  def arguments do
    [
      %{
        "name" => "symptom",
        "description" => "The observed problem (e.g., 'form doesn't update', 'data not loading', 'infinite loop')",
        "required" => true
      },
      %{
        "name" => "expected",
        "description" => "What behavior was expected instead",
        "required" => false
      },
      %{
        "name" => "component",
        "description" => "The LiveView or LiveComponent name",
        "required" => false
      }
    ]
  end

  @impl true
  def get(args) do
    symptom = Map.get(args, "symptom", "unexpected behavior")
    expected = Map.get(args, "expected")
    component = Map.get(args, "component")

    prompt_text = build_prompt(symptom, expected, component)

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
       ],
       "description" => "Use with timeline://latest resource for full context"
     }}
  end

  defp build_prompt(symptom, expected, component) do
    base = """
    Debug this LiveView issue:

    ## Symptom
    #{symptom}
    """

    base =
      if expected do
        base <>
          """

          ## Expected Behavior
          #{expected}
          """
      else
        base
      end

    base =
      if component do
        base <>
          """

          ## Component
          #{component}
          """
      else
        base
      end

    base <>
      """

      ## Debugging Steps

      1. **Read the timeline** using `timeline://latest` resource to see:
         - Event sequence (mount, handle_params, handle_event, render)
         - State changes at each step
         - Memory usage patterns

      2. **Look for these common issues:**
         - Missing or incorrect assigns in mount/0
         - handle_event not updating socket properly
         - handle_params not preserving state
         - Circular event triggers
         - Memory leaks from growing lists

      3. **Check the timeline for:**
         - Events that don't change state (no-op handlers)
         - Rapid event sequences (possible loops)
         - Memory growth patterns
         - Missing events you expected to see

      ## Analysis Request

      Please analyze the timeline and:
      1. Identify the root cause of: #{symptom}
      2. Show which events/state changes are problematic
      3. Provide a fix with corrected LiveView code
      4. Explain how to prevent this issue in the future
      """
  end
end
