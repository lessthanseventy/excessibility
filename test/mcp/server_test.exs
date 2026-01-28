defmodule Excessibility.MCP.ServerTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Server

  describe "server_info/0" do
    test "returns server name and version" do
      info = Server.server_info()

      assert info["name"] == "excessibility"
      assert is_binary(info["version"])
    end
  end

  describe "server_capabilities/0" do
    test "declares tools capability" do
      capabilities = Server.server_capabilities()

      assert Map.has_key?(capabilities, "tools")
    end
  end

  describe "__components__/0" do
    test "returns list of registered tools" do
      components = Server.__components__()

      tool_names = Enum.map(components, & &1.name)

      assert "e11y_check" in tool_names
      assert "e11y_debug" in tool_names
      assert "get_timeline" in tool_names
      assert "get_snapshots" in tool_names
    end
  end

  describe "__components__/1" do
    test "filters to tools only" do
      tools = Server.__components__(:tool)

      assert length(tools) == 4
      assert Enum.all?(tools, &match?(%Hermes.Server.Component.Tool{}, &1))
    end
  end
end
