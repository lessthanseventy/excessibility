defmodule Excessibility.MCP.Prompt do
  @moduledoc """
  Behaviour for MCP prompts.

  Prompts are reusable prompt templates that can be retrieved and filled with arguments.

  ## Example

      defmodule MyApp.MCP.Prompts.FixIssue do
        @behaviour Excessibility.MCP.Prompt

        @impl true
        def name, do: "fix-issue"

        @impl true
        def description, do: "Generate a prompt for fixing accessibility issues"

        @impl true
        def arguments do
          [
            %{
              "name" => "issue",
              "description" => "The accessibility issue to fix",
              "required" => true
            },
            %{
              "name" => "element",
              "description" => "The HTML element causing the issue",
              "required" => false
            }
          ]
        end

        @impl true
        def get(args) do
          issue = Map.get(args, "issue", "unknown issue")
          element = Map.get(args, "element")

          content = if element do
            "Fix this accessibility issue: \#{issue}\\n\\nElement: \#{element}"
          else
            "Fix this accessibility issue: \#{issue}"
          end

          {:ok, %{
            "messages" => [
              %{
                "role" => "user",
                "content" => %{
                  "type" => "text",
                  "text" => content
                }
              }
            ]
          }}
        end
      end

  ## Callbacks

  - `name/0` - String identifier for this prompt
  - `description/0` - Human-readable description
  - `arguments/0` - List of argument definitions
  - `get/1` - Returns the prompt content given arguments
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback arguments() :: [map()]
  @callback get(args :: map()) :: {:ok, map()} | {:error, String.t()}

  @doc """
  Returns MCP prompt definition for a prompt module.
  """
  def to_mcp_definition(prompt_module) do
    %{
      "name" => prompt_module.name(),
      "description" => prompt_module.description(),
      "arguments" => prompt_module.arguments()
    }
  end

  @doc """
  Formats a prompt get result for MCP response.
  """
  def format_result({:ok, prompt_data}) do
    prompt_data
  end

  def format_result({:error, message}) do
    %{"error" => message}
  end
end
