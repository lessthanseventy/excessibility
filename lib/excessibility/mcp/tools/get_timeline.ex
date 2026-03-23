defmodule Excessibility.MCP.Tools.GetTimeline do
  @moduledoc """
  MCP tool for reading captured timeline data.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext

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
        }
      }
    }
  end

  # Maximum timeline file size to process (256 KB)
  @max_file_size 256 * 1024

  @impl true
  def execute(args, _opts) do
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    default_path = ClientContext.client_path(Path.join(base_path, "timeline.json"))
    timeline_path = Map.get(args, "path") || default_path

    result =
      if File.exists?(timeline_path) do
        case File.stat(timeline_path) do
          {:ok, %{size: size}} when size > @max_file_size ->
            read_truncated_timeline(timeline_path, size)

          _ ->
            read_full_timeline(timeline_path)
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

  defp read_full_timeline(timeline_path) do
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
  end

  defp read_truncated_timeline(timeline_path, size) do
    case File.read(timeline_path) do
      {:ok, content} ->
        timeline = Jason.decode!(content)

        # Keep only the most recent test's timeline events
        truncated? = is_list(timeline["timeline"]) and length(timeline["timeline"]) > 200

        trimmed_timeline =
          if truncated? do
            Map.put(timeline, "timeline", Enum.take(timeline["timeline"], -200))
          else
            timeline
          end

        result = %{
          "status" => "success",
          "path" => timeline_path,
          "timeline" => trimmed_timeline
        }

        if truncated? do
          Map.put(result, "warning", "Timeline truncated to last 200 events (file was #{div(size, 1024)} KB)")
        else
          result
        end

      {:error, reason} ->
        %{
          "status" => "error",
          "error" => "Failed to read file: #{inspect(reason)}",
          "path" => timeline_path
        }
    end
  end
end
