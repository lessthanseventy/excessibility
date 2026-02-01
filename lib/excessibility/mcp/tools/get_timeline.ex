defmodule Excessibility.MCP.Tools.GetTimeline do
  @moduledoc """
  MCP tool for reading captured timeline data.
  """

  @behaviour Excessibility.MCP.Tool

  @impl true
  def name, do: "get_timeline"

  @impl true
  def description do
    "Read the captured timeline showing LiveView state evolution at each event."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "path" => %{
          "type" => "string",
          "description" => "Custom path to timeline.json (optional)"
        },
        "cwd" => %{
          "type" => "string",
          "description" =>
            "Working directory to look for timeline in (defaults to current directory). Required when testing projects other than excessibility itself."
        }
      }
    }
  end

  @impl true
  def execute(args, _opts) do
    cwd = Map.get(args, "cwd")
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

    default_path =
      if cwd && File.dir?(cwd) do
        Path.join([cwd, base_path, "timeline.json"])
      else
        Path.join(base_path, "timeline.json")
      end

    timeline_path = Map.get(args, "path") || default_path

    result =
      if File.exists?(timeline_path) do
        case File.read(timeline_path) do
          {:ok, content} ->
            %{
              "status" => "success",
              "path" => timeline_path,
              "timeline" => Jason.decode!(content)
            }

          {:error, reason} ->
            %{
              "status" => "error",
              "error" => "Failed to read file: #{inspect(reason)}",
              "path" => timeline_path
            }
        end
      else
        %{
          "status" => "not_found",
          "error" => "Timeline file not found",
          "path" => timeline_path
        }
      end

    {:ok, result}
  end
end
