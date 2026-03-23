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
  def description, do: "Excessibility and axe-core configuration"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def list do
    [
      %{
        "uri" => "config://excessibility",
        "name" => "Excessibility Config",
        "description" => "Current excessibility application configuration",
        "mimeType" => "application/json"
      }
    ]
  end

  @impl true
  def read("config://excessibility") do
    config = %{
      "excessibility_output_path" =>
        Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility"),
      "endpoint" => inspect(Application.get_env(:excessibility, :endpoint)),
      "axe_runner_path" => Application.get_env(:excessibility, :axe_runner_path),
      "axe_disable_rules" => Application.get_env(:excessibility, :axe_disable_rules, []),
      "head_render_path" => Application.get_env(:excessibility, :head_render_path, "/"),
      "custom_enrichers" => :excessibility |> Application.get_env(:custom_enrichers, []) |> Enum.map(&inspect/1),
      "custom_analyzers" => :excessibility |> Application.get_env(:custom_analyzers, []) |> Enum.map(&inspect/1)
    }

    {:ok, Jason.encode!(config, pretty: true)}
  end

  def read(uri) do
    {:error, "Unknown config URI: #{uri}"}
  end
end
