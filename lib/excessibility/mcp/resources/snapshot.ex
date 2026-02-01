defmodule Excessibility.MCP.Resources.Snapshot do
  @moduledoc """
  MCP resource for accessing HTML snapshots.
  """

  @behaviour Excessibility.MCP.Resource

  @impl true
  def uri_pattern, do: "snapshot://{name}"

  @impl true
  def name, do: "snapshot"

  @impl true
  def description, do: "HTML snapshots captured during accessibility tests"

  @impl true
  def mime_type, do: "text/html"

  @impl true
  def list do
    snapshots_dir = get_snapshots_dir()

    if File.dir?(snapshots_dir) do
      snapshots_dir
      |> Path.join("*.html")
      |> Path.wildcard()
      # Filter out diff files
      |> Enum.reject(&diff_file?/1)
      |> Enum.map(&snapshot_to_resource/1)
    else
      []
    end
  end

  @impl true
  def read("snapshot://" <> name) do
    snapshots_dir = get_snapshots_dir()
    path = Path.join(snapshots_dir, name)

    cond do
      not File.exists?(path) ->
        {:error, "Snapshot not found: #{name}"}

      String.contains?(name, "..") ->
        {:error, "Invalid snapshot name"}

      true ->
        File.read(path)
    end
  end

  def read(uri) do
    {:error, "Invalid snapshot URI: #{uri}"}
  end

  defp diff_file?(path) do
    String.contains?(path, ".good.html") or String.contains?(path, ".bad.html")
  end

  defp get_snapshots_dir do
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    Path.join(base_path, "html_snapshots")
  end

  defp snapshot_to_resource(path) do
    filename = Path.basename(path)
    stat = File.stat!(path)

    %{
      "uri" => "snapshot://#{filename}",
      "name" => filename,
      "description" => "HTML snapshot: #{filename}",
      "mimeType" => "text/html",
      "size" => stat.size
    }
  end
end
