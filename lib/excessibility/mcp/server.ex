defmodule Excessibility.MCP.Server do
  @moduledoc """
  MCP server for excessibility tools, resources, and prompts.

  Implements the MCP protocol for stdio transport:
  - JSON-RPC 2.0 message handling
  - initialize/initialized handshake
  - tools/list and tools/call
  - resources/list and resources/read
  - prompts/list and prompts/get

  ## Usage

      Excessibility.MCP.Server.start()

  Or via mix:

      mix run --no-halt -e "Excessibility.MCP.Server.start()"
  """

  use GenServer

  alias Excessibility.MCP.Prompt
  alias Excessibility.MCP.Registry
  alias Excessibility.MCP.Resource
  alias Excessibility.MCP.Tool

  @server_info %{
    "name" => "excessibility",
    "version" => "0.9.0"
  }

  @capabilities %{
    "tools" => %{},
    "resources" => %{"subscribe" => false, "listChanged" => false},
    "prompts" => %{"listChanged" => false}
  }

  defstruct [:cache]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Starts the MCP server, reading from stdin and writing to stdout.
  Blocks indefinitely processing messages.
  """
  def start do
    # Disable logger output to stdout (would corrupt MCP messages)
    Logger.configure(level: :none)

    {:ok, pid} = GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

    # Run the stdio loop in the current process
    loop(pid)
  end

  @doc """
  Starts the server as a supervised GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Handles a JSON-RPC message and returns a response.
  Useful for testing.
  """
  def handle_rpc(pid \\ __MODULE__, message) do
    GenServer.call(pid, {:handle_rpc, message})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{cache: %{}}}
  end

  @impl true
  def handle_call({:handle_rpc, message}, _from, state) do
    response = handle_message(message, state)
    {:reply, response, state}
  end

  # ============================================================================
  # Private - Message Loop
  # ============================================================================

  defp loop(pid) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line ->
        line
        |> String.trim()
        |> handle_line(pid)

        loop(pid)
    end
  end

  defp handle_line("", _pid), do: :ok

  defp handle_line(line, pid) do
    case Jason.decode(line) do
      {:ok, message} ->
        response = handle_rpc(pid, message)

        if response do
          send_response(response)
        end

      {:error, _} ->
        send_error(-32_700, "Parse error", nil)
    end
  end

  # ============================================================================
  # Private - Message Handlers
  # ============================================================================

  # Initialize request
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "initialize", "params" => params}, _state) do
    _client_info = Map.get(params, "clientInfo", %{})
    _protocol_version = Map.get(params, "protocolVersion")

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "protocolVersion" => "2024-11-05",
        "serverInfo" => @server_info,
        "capabilities" => @capabilities
      }
    }
  end

  # Initialized notification (no response needed)
  defp handle_message(%{"jsonrpc" => "2.0", "method" => "notifications/initialized"}, _state) do
    nil
  end

  # Tools list
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "tools/list"}, _state) do
    tools =
      Enum.map(Registry.discover_tools(), &Tool.to_mcp_definition/1)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "tools" => tools
      }
    }
  end

  # Tools call
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "tools/call", "params" => params}, _state) do
    tool_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    result = call_tool(tool_name, arguments)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  # Resources list
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "resources/list"}, _state) do
    resources =
      Enum.flat_map(Registry.discover_resources(), & &1.list())

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "resources" => resources
      }
    }
  end

  # Resources read
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "resources/read", "params" => params}, _state) do
    uri = Map.get(params, "uri")
    result = read_resource(uri)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  # Prompts list
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "prompts/list"}, _state) do
    prompts =
      Enum.map(Registry.discover_prompts(), &Prompt.to_mcp_definition/1)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{
        "prompts" => prompts
      }
    }
  end

  # Prompts get
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "prompts/get", "params" => params}, _state) do
    prompt_name = Map.get(params, "name")
    arguments = Map.get(params, "arguments", %{})

    result = get_prompt(prompt_name, arguments)

    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => result
    }
  end

  # Ping
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => "ping"}, _state) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "result" => %{}
    }
  end

  # Unknown method
  defp handle_message(%{"jsonrpc" => "2.0", "id" => id, "method" => method}, _state) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => -32_601,
        "message" => "Method not found: #{method}"
      }
    }
  end

  # Notifications (no id) - ignore
  defp handle_message(%{"jsonrpc" => "2.0", "method" => _method}, _state) do
    nil
  end

  defp handle_message(_other, _state) do
    nil
  end

  # ============================================================================
  # Private - Tool Execution
  # ============================================================================

  defp call_tool(name, args) do
    case Registry.get_tool(name) do
      nil ->
        %{
          "content" => [
            %{
              "type" => "text",
              "text" => Jason.encode!(%{"error" => "Unknown tool: #{name}"})
            }
          ],
          "isError" => true
        }

      tool_module ->
        result = tool_module.execute(args, [])
        Tool.format_result(result)
    end
  end

  # ============================================================================
  # Private - Resource Reading
  # ============================================================================

  defp read_resource(uri) do
    case Registry.get_resource_for_uri(uri) do
      nil ->
        %{"error" => "Resource not found: #{uri}"}

      resource_module ->
        result = resource_module.read(uri)
        Resource.format_result(result, uri, resource_module.mime_type())
    end
  end

  # ============================================================================
  # Private - Prompt Getting
  # ============================================================================

  defp get_prompt(name, args) do
    case Registry.get_prompt(name) do
      nil ->
        %{"error" => "Prompt not found: #{name}"}

      prompt_module ->
        result = prompt_module.get(args)
        Prompt.format_result(result)
    end
  end

  # ============================================================================
  # Private - Response Sending
  # ============================================================================

  defp send_response(response) do
    json = Jason.encode!(response)
    IO.write(:stdio, json <> "\n")
  end

  defp send_error(code, message, id) do
    response = %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => code,
        "message" => message
      }
    }

    send_response(response)
  end
end
