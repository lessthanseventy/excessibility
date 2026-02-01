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
      assert "e11y_check" in tool_names
      assert "e11y_debug" in tool_names
      assert "get_timeline" in tool_names
      assert "get_snapshots" in tool_names
      assert "analyze_timeline" in tool_names
      assert "suggest_fixes" in tool_names

      # Verify tool structure
      e11y_check = Enum.find(tools, &(&1["name"] == "e11y_check"))
      assert e11y_check["description"]
      assert e11y_check["inputSchema"]["type"] == "object"
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
    test "returns list of available prompts", %{server: pid} do
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

      prompt_names = Enum.map(prompts, & &1["name"])
      assert "fix-a11y-issue" in prompt_names
      assert "debug-liveview" in prompt_names

      # Verify prompt structure
      fix_prompt = Enum.find(prompts, &(&1["name"] == "fix-a11y-issue"))
      assert fix_prompt["description"]
      assert is_list(fix_prompt["arguments"])
    end
  end

  describe "prompts/get" do
    test "gets fix-a11y-issue prompt", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "prompts/get",
        "params" => %{
          "name" => "fix-a11y-issue",
          "arguments" => %{
            "issue" => "Missing form label",
            "element" => "<input type='text' />"
          }
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1

      messages = response["result"]["messages"]
      assert is_list(messages)
      assert length(messages) == 1

      user_message = hd(messages)
      assert user_message["role"] == "user"
      assert user_message["content"]["type"] == "text"
      assert user_message["content"]["text"] =~ "Missing form label"
      assert user_message["content"]["text"] =~ "<input type='text' />"
    end

    test "gets debug-liveview prompt", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "prompts/get",
        "params" => %{
          "name" => "debug-liveview",
          "arguments" => %{
            "symptom" => "Form doesn't update",
            "expected" => "Form should show validation errors"
          }
        }
      }

      response = Server.handle_rpc(pid, message)

      assert response["result"]["messages"]
      message_text = hd(response["result"]["messages"])["content"]["text"]
      assert message_text =~ "Form doesn't update"
      assert message_text =~ "Form should show validation errors"
    end

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
  # Tool Integration Tests
  # ============================================================================

  describe "e11y_debug tool" do
    test "returns output from mix command", %{server: pid} do
      # Test with a non-existent file - mix should fail fast with an error message
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "e11y_debug",
          "arguments" => %{
            "test_args" => "test/nonexistent_file_12345.exs",
            "timeout" => 30_000
          }
        }
      }

      start = System.monotonic_time(:millisecond)
      response = Server.handle_rpc(pid, message)
      elapsed = System.monotonic_time(:millisecond) - start

      # Should not hang
      assert elapsed < 10_000, "Tool took #{elapsed}ms - should complete quickly"

      # Should return valid response
      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1
      assert response["result"]["content"]

      content = hd(response["result"]["content"])
      assert content["type"] == "text"

      result = Jason.decode!(content["text"])

      # Should have captured output
      assert Map.has_key?(result, "output")
      assert Map.has_key?(result, "exit_code")
      assert Map.has_key?(result, "status")

      # Output should contain something (error message about file not found)
      assert is_binary(result["output"])
      assert String.length(result["output"]) > 0
    end

    @tag :slow
    test "respects timeout and returns timeout error", %{server: pid} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{
          "name" => "e11y_debug",
          "arguments" => %{
            # Use a command that will definitely take more than 100ms
            "test_args" => "test/nonexistent_test.exs",
            "timeout" => 100
          }
        }
      }

      start = System.monotonic_time(:millisecond)
      response = Server.handle_rpc(pid, message)
      elapsed = System.monotonic_time(:millisecond) - start

      assert response["jsonrpc"] == "2.0"
      assert response["id"] == 1

      content = hd(response["result"]["content"])
      result = Jason.decode!(content["text"])

      # Should either timeout or fail quickly (file doesn't exist)
      assert result["status"] in ["failure", "error"] or result["output"] =~ "timed out"

      # Most importantly: should not hang - should complete in reasonable time
      assert elapsed < 5000, "Tool call took #{elapsed}ms - should not hang"
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
