defmodule Excessibility.MCP.Resource do
  @moduledoc """
  Behaviour for MCP resources.

  Resources provide read-only data that can be accessed via URIs.

  ## Example

      defmodule MyApp.MCP.Resources.Config do
        @behaviour Excessibility.MCP.Resource

        @impl true
        def uri_pattern, do: "config://{name}"

        @impl true
        def name, do: "config"

        @impl true
        def description, do: "Application configuration"

        @impl true
        def mime_type, do: "application/json"

        @impl true
        def list do
          [
            %{
              "uri" => "config://app",
              "name" => "app",
              "description" => "App config",
              "mimeType" => "application/json"
            }
          ]
        end

        @impl true
        def read("config://app") do
          {:ok, Jason.encode!(%{setting: "value"})}
        end

        def read(_uri), do: {:error, "Resource not found"}
      end

  ## Callbacks

  - `uri_pattern/0` - URI template pattern (e.g., "timeline://latest")
  - `name/0` - Human-readable name for this resource type
  - `description/0` - Description of what this resource provides
  - `mime_type/0` - MIME type of the resource content
  - `list/0` - Returns list of available resource instances
  - `read/1` - Reads a specific resource by URI
  """

  @callback uri_pattern() :: String.t()
  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback mime_type() :: String.t()
  @callback list() :: [map()]
  @callback read(uri :: String.t()) :: {:ok, String.t()} | {:error, String.t()}

  @doc """
  Formats a resource read result for MCP response.
  """
  def format_result({:ok, content}, uri, mime_type) do
    %{
      "contents" => [
        %{
          "uri" => uri,
          "mimeType" => mime_type,
          "text" => content
        }
      ]
    }
  end

  def format_result({:error, message}, _uri, _mime_type) do
    %{
      "error" => message
    }
  end

  @doc """
  Returns MCP resource definition for a resource module.
  """
  def to_mcp_definition(resource_module) do
    %{
      "uri" => resource_module.uri_pattern(),
      "name" => resource_module.name(),
      "description" => resource_module.description(),
      "mimeType" => resource_module.mime_type()
    }
  end

  @doc """
  Checks if a URI matches a resource module's pattern.

  Supports simple patterns like:
  - "timeline://latest" (exact match)
  - "snapshot://{name}" (matches any snapshot://...)
  - "config://{type}" (matches any config://...)
  """
  def matches_uri?(resource_module, uri) do
    pattern = resource_module.uri_pattern()

    cond do
      # Exact match
      pattern == uri ->
        true

      # Pattern with placeholder like "snapshot://{name}"
      String.contains?(pattern, "{") ->
        # Extract the scheme from both pattern and URI
        pattern_scheme = pattern |> String.split("://") |> List.first()
        uri_scheme = uri |> String.split("://") |> List.first()
        pattern_scheme == uri_scheme

      true ->
        false
    end
  end
end
