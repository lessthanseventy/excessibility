defmodule Excessibility.MCP.Tool do
  @moduledoc """
  Behaviour for MCP tools.

  Tools are executable actions that can be called via the MCP protocol.

  ## Example

      defmodule MyApp.MCP.Tools.MyTool do
        @behaviour Excessibility.MCP.Tool

        @impl true
        def name, do: "my_tool"

        @impl true
        def description, do: "Does something useful"

        @impl true
        def input_schema do
          %{
            "type" => "object",
            "properties" => %{
              "arg1" => %{"type" => "string", "description" => "First argument"}
            },
            "required" => ["arg1"]
          }
        end

        @impl true
        def execute(args, _opts) do
          {:ok, %{"result" => args["arg1"]}}
        end
      end

  ## Callbacks

  - `name/0` - Returns string identifier for this tool
  - `description/0` - Human-readable description of what the tool does
  - `input_schema/0` - JSON Schema for the tool's input arguments
  - `execute/2` - Takes args map and opts keyword list, returns result

  ## Options

  The `opts` keyword list may contain:
  - `:progress_callback` - Function to call with progress updates
  """

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback input_schema() :: map()
  @callback execute(args :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, String.t()}

  @doc """
  Formats a successful tool result for MCP response.
  """
  def format_result({:ok, data}) do
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => Jason.encode!(data)
        }
      ]
    }
  end

  def format_result({:error, message}) do
    %{
      "content" => [
        %{
          "type" => "text",
          "text" => Jason.encode!(%{"error" => message})
        }
      ],
      "isError" => true
    }
  end

  @doc """
  Returns the MCP tool definition for a tool module.
  """
  def to_mcp_definition(tool_module) do
    %{
      "name" => tool_module.name(),
      "description" => tool_module.description(),
      "inputSchema" => tool_module.input_schema()
    }
  end
end
