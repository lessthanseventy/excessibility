defmodule Excessibility.MCP.Resources.Timeline do
  @moduledoc """
  MCP resource for accessing timeline data.
  """

  @behaviour Excessibility.MCP.Resource

  @impl true
  def uri_pattern, do: "timeline://latest"

  @impl true
  def name, do: "timeline"

  @impl true
  def description, do: "LiveView timeline showing state evolution at each event"

  @impl true
  def mime_type, do: "application/json"

  @impl true
  def list do
    timeline_path = get_timeline_path()

    if File.exists?(timeline_path) do
      stat = File.stat!(timeline_path)

      [
        %{
          "uri" => "timeline://latest",
          "name" => "Latest Timeline",
          "description" => "Most recent timeline capture",
          "mimeType" => "application/json",
          "size" => stat.size,
          "mtime" => DateTime.to_iso8601(stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC"))
        }
      ]
    else
      []
    end
  end

  @impl true
  def read("timeline://latest") do
    timeline_path = get_timeline_path()

    if File.exists?(timeline_path) do
      File.read(timeline_path)
    else
      {:error, "Timeline file not found at #{timeline_path}"}
    end
  end

  def read(uri) do
    {:error, "Unknown timeline URI: #{uri}"}
  end

  defp get_timeline_path do
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    Path.join(base_path, "timeline.json")
  end
end
