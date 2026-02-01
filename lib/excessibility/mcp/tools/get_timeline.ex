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

  @impl true
  def execute(args, _opts) do
    base_path = Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
    default_path = ClientContext.client_path(Path.join(base_path, "timeline.json"))
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
