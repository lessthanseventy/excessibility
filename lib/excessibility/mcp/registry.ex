defmodule Excessibility.MCP.Registry do
  @moduledoc """
  Auto-discovers MCP tools, resources, and prompts at compile time.

  Built-in modules are discovered from:
  - `lib/excessibility/mcp/tools/` - Tool modules
  - `lib/excessibility/mcp/resources/` - Resource modules
  - `lib/excessibility/mcp/prompts/` - Prompt modules

  ## Custom Plugins

  Users can register custom modules via application config:

      # config/test.exs
      config :excessibility,
        custom_mcp_tools: [MyApp.MCP.Tools.Custom],
        custom_mcp_resources: [MyApp.MCP.Resources.Custom],
        custom_mcp_prompts: [MyApp.MCP.Prompts.Custom]

  Custom modules must implement the appropriate behaviour.

  ## Usage

      # Get all tools (built-in + custom)
      Registry.discover_tools()

      # Get tool by name
      Registry.get_tool("e11y_check")

      # Get all resources
      Registry.discover_resources()

      # Find resource for URI
      Registry.get_resource_for_uri("snapshot://test.html")
  """

  @tool_behaviour Excessibility.MCP.Tool
  @resource_behaviour Excessibility.MCP.Resource
  @prompt_behaviour Excessibility.MCP.Prompt

  # Compile-time discovery helper functions
  file_to_module = fn path, subdir ->
    module_name =
      path
      |> Path.basename(".ex")
      |> Macro.camelize()

    subdir_name = Macro.camelize(subdir)
    Module.concat([Excessibility.MCP, subdir_name, module_name])
  end

  implements_behaviour? = fn module, behaviour ->
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        behaviour in behaviours

      {:error, _} ->
        false
    end
  end

  discover_modules = fn subdir, behaviour ->
    base_path = Path.join([__DIR__, subdir])

    if File.dir?(base_path) do
      base_path
      |> Path.join("*.ex")
      |> Path.wildcard()
      |> Enum.map(&file_to_module.(&1, subdir))
      |> Enum.filter(&implements_behaviour?.(&1, behaviour))
      |> Enum.sort_by(& &1.name())
    else
      []
    end
  end

  # Built-in plugins discovered at compile time
  @builtin_tools discover_modules.("tools", @tool_behaviour)
  @builtin_resources discover_modules.("resources", @resource_behaviour)
  @builtin_prompts discover_modules.("prompts", @prompt_behaviour)

  @doc """
  Returns all registered tools (built-in + custom).

  Custom tools can be configured via `:custom_mcp_tools` in app config.
  """
  def discover_tools do
    custom = Application.get_env(:excessibility, :custom_mcp_tools, [])
    valid_custom = Enum.filter(custom, &valid_tool?/1)
    merge_plugins(@builtin_tools, valid_custom)
  end

  @doc """
  Returns all registered resources (built-in + custom).

  Custom resources can be configured via `:custom_mcp_resources` in app config.
  """
  def discover_resources do
    custom = Application.get_env(:excessibility, :custom_mcp_resources, [])
    valid_custom = Enum.filter(custom, &valid_resource?/1)
    merge_plugins(@builtin_resources, valid_custom)
  end

  @doc """
  Returns all registered prompts (built-in + custom).

  Custom prompts can be configured via `:custom_mcp_prompts` in app config.
  """
  def discover_prompts do
    custom = Application.get_env(:excessibility, :custom_mcp_prompts, [])
    valid_custom = Enum.filter(custom, &valid_prompt?/1)
    merge_plugins(@builtin_prompts, valid_custom)
  end

  @doc """
  Finds a tool by name.

  Returns nil if not found.
  """
  def get_tool(name) do
    Enum.find(discover_tools(), fn tool ->
      tool.name() == name
    end)
  end

  @doc """
  Finds a resource by name.

  Returns nil if not found.
  """
  def get_resource(name) do
    Enum.find(discover_resources(), fn resource ->
      resource.name() == name
    end)
  end

  @doc """
  Finds a resource that can handle the given URI.

  Returns nil if no matching resource found.
  """
  def get_resource_for_uri(uri) do
    alias Excessibility.MCP.Resource

    Enum.find(discover_resources(), fn resource ->
      Resource.matches_uri?(resource, uri)
    end)
  end

  @doc """
  Finds a prompt by name.

  Returns nil if not found.
  """
  def get_prompt(name) do
    Enum.find(discover_prompts(), fn prompt ->
      prompt.name() == name
    end)
  end

  # Validates that a module implements the Tool behaviour
  defp valid_tool?(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        @tool_behaviour in behaviours

      {:error, _} ->
        false
    end
  end

  # Validates that a module implements the Resource behaviour
  defp valid_resource?(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        @resource_behaviour in behaviours

      {:error, _} ->
        false
    end
  end

  # Validates that a module implements the Prompt behaviour
  defp valid_prompt?(module) do
    case Code.ensure_compiled(module) do
      {:module, _} ->
        behaviours = module.__info__(:attributes)[:behaviour] || []
        @prompt_behaviour in behaviours

      {:error, _} ->
        false
    end
  end

  # Merges built-in and custom plugins, sorted by name, no duplicates
  defp merge_plugins(builtin, custom) do
    (builtin ++ custom)
    |> Enum.uniq()
    |> Enum.sort_by(& &1.name())
  end
end
