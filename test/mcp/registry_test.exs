defmodule Excessibility.MCP.RegistryTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Registry

  describe "discover_tools/0" do
    test "discovers built-in tools" do
      tools = Registry.discover_tools()

      assert is_list(tools)
      assert length(tools) >= 3

      tool_names = Enum.map(tools, & &1.name())
      assert "get_timeline" in tool_names
      assert "get_snapshots" in tool_names
      assert "generate_test" in tool_names
    end

    test "tools implement Tool behaviour" do
      tools = Registry.discover_tools()

      for tool <- tools do
        assert is_binary(tool.name())
        assert is_binary(tool.description())
        assert is_map(tool.input_schema())
      end
    end
  end

  describe "get_tool/1" do
    test "finds tool by name" do
      tool = Registry.get_tool("get_snapshots")

      assert tool
      assert tool.name() == "get_snapshots"
    end

    test "returns nil for unknown tool" do
      assert Registry.get_tool("nonexistent") == nil
    end
  end

  describe "discover_resources/0" do
    test "discovers built-in resources" do
      resources = Registry.discover_resources()

      assert is_list(resources)
      assert length(resources) >= 2

      resource_names = Enum.map(resources, & &1.name())
      assert "config" in resource_names
      assert "snapshot" in resource_names
    end

    test "resources implement Resource behaviour" do
      resources = Registry.discover_resources()

      for resource <- resources do
        assert is_binary(resource.uri_pattern())
        assert is_binary(resource.name())
        assert is_binary(resource.description())
        assert is_binary(resource.mime_type())
        assert is_list(resource.list())
      end
    end
  end

  describe "get_resource/1" do
    test "finds resource by name" do
      resource = Registry.get_resource("config")

      assert resource
      assert resource.name() == "config"
    end

    test "returns nil for unknown resource" do
      assert Registry.get_resource("nonexistent") == nil
    end
  end

  describe "get_resource_for_uri/1" do
    test "finds resource for pattern URI match" do
      resource = Registry.get_resource_for_uri("snapshot://test.html")

      assert resource
      assert resource.name() == "snapshot"
    end

    test "finds config resource" do
      resource = Registry.get_resource_for_uri("config://excessibility")

      assert resource
      assert resource.name() == "config"
    end

    test "returns nil for unknown URI" do
      assert Registry.get_resource_for_uri("unknown://something") == nil
    end
  end

  describe "discover_prompts/0" do
    test "returns empty list (all prompts removed)" do
      prompts = Registry.discover_prompts()

      assert is_list(prompts)
      assert prompts == []
    end
  end

  describe "get_prompt/1" do
    test "returns nil for unknown prompt" do
      assert Registry.get_prompt("nonexistent") == nil
    end
  end
end
