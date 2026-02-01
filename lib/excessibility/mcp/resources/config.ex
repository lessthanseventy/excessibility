defmodule Excessibility.MCP.Resources.Config do
  @moduledoc """
  MCP resource for accessing excessibility configuration.
  """

  @behaviour Excessibility.MCP.Resource

  @impl true
  def uri_pattern, do: "config://{type}"

  @impl true
  def name, do: "config"

  @impl true
  def description, do: "Excessibility and Pa11y configuration"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def list do
    resources = [
      %{
        "uri" => "config://excessibility",
        "name" => "Excessibility Config",
        "description" => "Current excessibility application configuration",
        "mimeType" => "application/json"
      }
    ]

    # Add Pa11y config if it exists
    pa11y_path = get_pa11y_config_path()

    if File.exists?(pa11y_path) do
      resources ++
        [
          %{
            "uri" => "config://pa11y",
            "name" => "Pa11y Config",
            "description" => "Pa11y accessibility checker configuration",
            "mimeType" => "application/json"
          }
        ]
    else
      resources
    end
  end

  @impl true
  def read("config://excessibility") do
    config = %{
      "excessibility_output_path" =>
        Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility"),
      "endpoint" => inspect(Application.get_env(:excessibility, :endpoint)),
      "pa11y_path" => Application.get_env(:excessibility, :pa11y_path),
      "pa11y_config" => Application.get_env(:excessibility, :pa11y_config, "pa11y.json"),
      "head_render_path" => Application.get_env(:excessibility, :head_render_path, "/"),
      "custom_enrichers" => :excessibility |> Application.get_env(:custom_enrichers, []) |> Enum.map(&inspect/1),
      "custom_analyzers" => :excessibility |> Application.get_env(:custom_analyzers, []) |> Enum.map(&inspect/1)
    }

    {:ok, Jason.encode!(config, pretty: true)}
  end

  def read("config://pa11y") do
    pa11y_path = get_pa11y_config_path()

    if File.exists?(pa11y_path) do
      File.read(pa11y_path)
    else
      {:error, "Pa11y config not found at #{pa11y_path}"}
    end
  end

  def read(uri) do
    {:error, "Unknown config URI: #{uri}"}
  end

  defp get_pa11y_config_path do
    Application.get_env(:excessibility, :pa11y_config, "pa11y.json")
  end
end
