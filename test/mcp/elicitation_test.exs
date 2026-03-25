defmodule Excessibility.MCP.ElicitationTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Elicitation

  # ============================================================================
  # build_request/3
  # ============================================================================

  describe "build_request/3" do
    test "returns a JSON-RPC 2.0 map with elicitation/create method" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "approved" => %{"type" => "boolean", "description" => "Do you approve?"}
        }
      }

      result = Elicitation.build_request(1, "Please confirm", schema)

      assert result == %{
               "jsonrpc" => "2.0",
               "id" => 1,
               "method" => "elicitation/create",
               "params" => %{
                 "message" => "Please confirm",
                 "requestedSchema" => schema
               }
             }
    end

    test "uses the given id" do
      result = Elicitation.build_request(42, "msg", %{})
      assert result["id"] == 42
    end

    test "preserves complex schemas" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "count" => %{"type" => "integer", "minimum" => 0}
        },
        "required" => ["name"]
      }

      result = Elicitation.build_request(1, "Enter details", schema)
      assert result["params"]["requestedSchema"] == schema
    end
  end

  # ============================================================================
  # parse_response/1
  # ============================================================================

  describe "parse_response/1" do
    test "returns {:accept, content} when action is accept" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{
          "action" => "accept",
          "content" => %{"approved" => true}
        }
      }

      assert {:accept, %{"approved" => true}} = Elicitation.parse_response(response)
    end

    test "returns :decline when action is decline" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{
          "action" => "decline"
        }
      }

      assert :decline = Elicitation.parse_response(response)
    end

    test "returns :cancel when action is cancel" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{
          "action" => "cancel"
        }
      }

      assert :cancel = Elicitation.parse_response(response)
    end

    test "returns {:error, :invalid_response} for unexpected action" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{
          "action" => "unknown"
        }
      }

      assert {:error, :invalid_response} = Elicitation.parse_response(response)
    end

    test "returns {:error, :invalid_response} when result key is missing" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1
      }

      assert {:error, :invalid_response} = Elicitation.parse_response(response)
    end

    test "returns {:accept, content} with complex content" do
      content = %{"name" => "test", "count" => 5, "nested" => %{"key" => "value"}}

      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{
          "action" => "accept",
          "content" => content
        }
      }

      assert {:accept, ^content} = Elicitation.parse_response(response)
    end
  end

  # ============================================================================
  # build_callback/2
  # ============================================================================

  describe "build_callback/2" do
    test "returns nil when write_fn is nil" do
      read_fn = fn -> "data" end
      assert Elicitation.build_callback(nil, read_fn) == nil
    end

    test "returns nil when read_fn is nil" do
      write_fn = fn _data -> :ok end
      assert Elicitation.build_callback(write_fn, nil) == nil
    end

    test "returns nil when both are nil" do
      assert Elicitation.build_callback(nil, nil) == nil
    end

    test "returns a 2-arity function when both fns provided" do
      write_fn = fn _data -> :ok end
      read_fn = fn -> "{}" end

      callback = Elicitation.build_callback(write_fn, read_fn)
      assert is_function(callback, 2)
    end

    test "callback writes JSON request and reads/parses response" do
      test_pid = self()

      schema = %{
        "type" => "object",
        "properties" => %{
          "ok" => %{"type" => "boolean"}
        }
      }

      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{
          "action" => "accept",
          "content" => %{"ok" => true}
        }
      }

      write_fn = fn data ->
        send(test_pid, {:written, data})
        :ok
      end

      read_fn = fn ->
        Jason.encode!(response)
      end

      callback = Elicitation.build_callback(write_fn, read_fn)
      result = callback.("Do you confirm?", schema)

      assert {:accept, %{"ok" => true}} = result

      # Verify the written data is valid JSON with a newline
      assert_receive {:written, written_data}
      assert String.ends_with?(written_data, "\n")

      decoded = Jason.decode!(String.trim(written_data))
      assert decoded["jsonrpc"] == "2.0"
      assert decoded["method"] == "elicitation/create"
      assert decoded["params"]["message"] == "Do you confirm?"
      assert decoded["params"]["requestedSchema"] == schema
      assert is_integer(decoded["id"])
    end

    test "callback handles decline response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"action" => "decline"}
      }

      write_fn = fn _data -> :ok end
      read_fn = fn -> Jason.encode!(response) end

      callback = Elicitation.build_callback(write_fn, read_fn)
      assert :decline = callback.("Question?", %{})
    end

    test "callback handles cancel response" do
      response = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "result" => %{"action" => "cancel"}
      }

      write_fn = fn _data -> :ok end
      read_fn = fn -> Jason.encode!(response) end

      callback = Elicitation.build_callback(write_fn, read_fn)
      assert :cancel = callback.("Question?", %{})
    end

    test "callback handles invalid JSON gracefully" do
      write_fn = fn _data -> :ok end
      read_fn = fn -> "not valid json{{{" end

      callback = Elicitation.build_callback(write_fn, read_fn)
      assert {:error, :invalid_json} = callback.("Question?", %{})
    end
  end
end
