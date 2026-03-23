defmodule Excessibility.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Server

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Start a fresh server for each test
    {:ok, pid} = GenServer.start_link(Server, [], [])
    {:ok, server: pid}
  end

  # ============================================================================
  # Public API Tests
  # ============================================================================

  describe "start/0" do
    test "function exists" do
      {:module, _} = Code.ensure_loaded(Server)
      assert {:start, 0} in Server.__info__(:functions)
    end
  end

  describe "start_link/1" do
    test "starts server as GenServer" do
      assert {:ok, pid} = Server.start_link([])
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Initialize Tests
  # ============================================================================

  describe "initialize" do
    test "returns protocol info and capabilities", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{
          "protocolVersion" => "2024-11-05",
          "clientInfo" => %{"name" => "test"}
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["protocolVersion"] == "2024-11-05"
      assert response["result"]["serverInfo"]["name"] == "excessibility"
      assert response["result"]["capabilities"]["tools"] == %{}
      assert response["result"]["capabilities"]["resources"]["subscribe"] == false
      assert response["result"]["capabilities"]["prompts"]["listChanged"] == false
    end
  end

  # ============================================================================
  # Tools Tests
  # ============================================================================

  describe "tools/list" do
    test "returns list of available tools", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list"
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1

      tools = response["result"]["tools"]
      assert is_list(tools)

      # Check for expected tools
      tool_names = Enum.map(tools, & &1["name"])
      assert "get_timeline" in tool_names
      assert "get_snapshots" in tool_names
      assert "generate_test" in tool_names

      # Verify tool structure
      get_snapshots = Enum.find(tools, &(&1["name"] == "get_snapshots"))
      assert get_snapshots["description"]
      assert get_snapshots["inputSchema"]["type"] == "object"
    end
  end

  describe "tools/call" do
    test "calls get_timeline tool", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_timeline",
          "arguments" => %{}
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["content"]

      content = hd(response["result"]["content"])
      assert content["type"] == "text"
      result = Jason.decode!(content["text"])
      # File might not exist, but we should get a valid response structure
      assert result["status"] in ["success", "not_found"]
    end

    test "calls get_snapshots tool", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "get_snapshots",
          "arguments" => %{}
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      content = hd(response["result"]["content"])
      result = Jason.decode!(content["text"])
      assert result["status"] in ["success", "not_found"]
    end

    test "returns error for unknown tool", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "nonexistent_tool",
          "arguments" => %{}
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["result"]["isError"] == true
      content = hd(response["result"]["content"])
      result = Jason.decode!(content["text"])
      assert result["error"] =~ "Unknown tool"
    end
  end

  # ============================================================================
  # Resources Tests
  # ============================================================================

  describe "resources/list" do
    test "returns list of available resources", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "resources/list"
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1

      resources = response["result"]["resources"]
      assert is_list(resources)

      # Should always have at least the excessibility config
      resource_uris =
        Enum.map(resources, & &1["uri"])

      assert "config://excessibility" in resource_uris
    end
  end

  describe "resources/read" do
    test "reads excessibility config", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "resources/read",
        "params" => %{
          "uri" => "config://excessibility"
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1

      contents = response["result"]["contents"]
      assert is_list(contents)
      assert length(contents) == 1

      content = hd(contents)
      assert content["uri"] == "config://excessibility"
      assert content["mimeType"] == "application/json"

      config = Jason.decode!(content["text"])
      assert Map.has_key?(config, "excessibility_output_path")
    end

    test "returns error for unknown resource", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "resources/read",
        "params" => %{
          "uri" => "unknown://resource"
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["result"]["error"] =~ "Resource not found"
    end
  end

  # ============================================================================
  # Prompts Tests
  # ============================================================================

  describe "prompts/list" do
    test "returns empty list (all prompts removed)", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "prompts/list"
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1

      prompts = response["result"]["prompts"]
      assert is_list(prompts)
      assert prompts == []
    end
  end

  describe "prompts/get" do
    test "returns error for unknown prompt", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "prompts/get",
        "params" => %{
          "name" => "nonexistent-prompt",
          "arguments" => %{}
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["result"]["error"] =~ "Prompt not found"
    end
  end

  # ============================================================================
  # Ping & Error Handling Tests
  # ============================================================================

  describe "ping" do
    test "responds to ping", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "ping"
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"] == %{}
    end
  end

  describe "unknown method" do
    test "returns method not found error", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "unknown/method"
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["error"]["code"] == -32_601
      assert response["error"]["message"] =~ "Method not found"
    end
  end

  describe "notifications" do
    test "returns nil for initialized notification", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized"
      }

      response = Server.handle_rpc(pid, message)

      assert response == nil
    end
  end
end
