defmodule Excessibility.MCP.RegistryTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Registry

  describe "discover_tools/0" do
    test "discovers built-in tools" do
      tools = Registry.discover_tools()

      assert is_list(tools)
      assert length(tools) >= 6

      tool_names = Enum.map(tools, & &1.name())
      assert "e11y_check" in tool_names
      assert "e11y_debug" in tool_names
      assert "get_timeline" in tool_names
      assert "get_snapshots" in tool_names
      assert "analyze_timeline" in tool_names
      assert "suggest_fixes" in tool_names
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
      tool = Registry.get_tool("e11y_check")

      assert tool
      assert tool.name() == "e11y_check"
    end

    test "returns nil for unknown tool" do
      assert Registry.get_tool("nonexistent") == nil
    end
  end

  describe "discover_resources/0" do
    test "discovers built-in resources" do
      resources = Registry.discover_resources()

      assert is_list(resources)
      assert length(resources) >= 3

      resource_names = Enum.map(resources, & &1.name())
      assert "config" in resource_names
      assert "snapshot" in resource_names
      assert "timeline" in resource_names
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
    test "finds resource for exact URI match" do
      resource = Registry.get_resource_for_uri("timeline://latest")

      assert resource
      assert resource.name() == "timeline"
    end

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
    test "discovers built-in prompts" do
      prompts = Registry.discover_prompts()

      assert is_list(prompts)
      assert length(prompts) >= 2

      prompt_names = Enum.map(prompts, & &1.name())
      assert "fix-a11y-issue" in prompt_names
      assert "debug-liveview" in prompt_names
    end

    test "prompts implement Prompt behaviour" do
      prompts = Registry.discover_prompts()

      for prompt <- prompts do
        assert is_binary(prompt.name())
        assert is_binary(prompt.description())
        assert is_list(prompt.arguments())
      end
    end
  end

  describe "get_prompt/1" do
    test "finds prompt by name" do
      prompt = Registry.get_prompt("fix-a11y-issue")

      assert prompt
      assert prompt.name() == "fix-a11y-issue"
    end

    test "returns nil for unknown prompt" do
      assert Registry.get_prompt("nonexistent") == nil
    end
  end
end
