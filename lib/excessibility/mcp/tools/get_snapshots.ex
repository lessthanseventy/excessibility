defmodule Excessibility.MCP.Tools.GetSnapshots do
  @moduledoc """
  MCP tool for listing or reading HTML snapshots.
  """

  @behaviour Excessibility.MCP.Tool

  @impl true
  def name, do: "get_snapshots"

  @impl true
  def description do
    "List or read HTML snapshots captured during tests."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "filter" => %{
          "type" => "string",
          "description" => "Glob pattern to filter snapshots (e.g., '*_test_*.html')"
        },
        "include_content" => %{
          "type" => "boolean",
          "description" => "Include HTML content in response"
        },
        "cwd" => %{
          "type" => "string",
          "description" =>
            "Working directory to look for snapshots in (defaults to current directory). Required when testing projects other than excessibility itself."
        }
      }
    }
  end

  @impl true
  def execute(args, _opts) do
    cwd = Map.get(args, "cwd")
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

    snapshots_dir =
      if cwd && File.dir?(cwd) do
        Path.join([cwd, base_path, "html_snapshots"])
      else
        Path.join(base_path, "html_snapshots")
      end
    filter = Map.get(args, "filter", "*.html")
    include_content? = Map.get(args, "include_content", false)

    result =
      if File.dir?(snapshots_dir) do
        pattern = Path.join(snapshots_dir, filter)

        snapshots =
          pattern
          |> Path.wildcard()
          # Filter out diff files
          |> Enum.reject(&diff_file?/1)
          |> Enum.map(&build_snapshot(&1, include_content?))

        %{
          "status" => "success",
          "count" => length(snapshots),
          "snapshots" => snapshots
        }
      else
        %{
          "status" => "not_found",
          "error" => "Snapshots directory not found",
          "path" => snapshots_dir
        }
      end

    {:ok, result}
  end

  defp diff_file?(path) do
    String.contains?(path, ".good.html") or String.contains?(path, ".bad.html")
  end

  defp build_snapshot(path, include_content?) do
    snapshot = %{
      "filename" => Path.basename(path),
      "path" => path,
      "size" => File.stat!(path).size
    }

    if include_content? do
      Map.put(snapshot, "content", File.read!(path))
    else
      snapshot
    end
  end
end
