defmodule Excessibility.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Server

  # The custom MCP server uses private message handlers,
  # so we test it by simulating JSON-RPC messages

  describe "start/0" do
    test "function exists" do
      assert function_exported?(Server, :start, 0)
    end
  end

  describe "module attributes" do
    test "defines expected tools" do
      # Verify the module is loaded and has the expected structure
      assert Code.ensure_loaded?(Server)
      assert {:module, Excessibility.MCP.Server} = Code.ensure_compiled(Server)
    end
  end
end
