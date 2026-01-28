defmodule Excessibility.TelemetryCapture.Enrichers.ComponentTree do
  @moduledoc """
  Enriches timeline events with LiveComponent structure information.

  Tracks:
  - Count of LiveComponents in assigns
  - Component IDs (CIDs) present
  - Stateful component count
  - Maximum nesting depth to components

  ## Detection

  Identifies `Phoenix.LiveComponent.CID` structs which represent
  component IDs. These appear in assigns when using `@myself` or
  when component references are stored.

  ## Example Output

      %{
        sequence: 3,
        event: "handle_event:click",
        component_count: 2,
        component_ids: [1, 5],
        stateful_components: 2,
        component_depth: 2
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :component_tree
  def cost, do: :moderate

  def enrich(assigns, _opts) do
    {cids, max_depth} = find_components(assigns)

    %{
      component_count: length(cids),
      component_ids: cids,
      stateful_components: length(cids),
      component_depth: max_depth
    }
  end

  defp find_components(data) do
    {cids, depth} = traverse(data, 0)
    {Enum.uniq(cids), depth}
  end

  defp traverse(%Phoenix.LiveComponent.CID{cid: cid}, depth) do
    {[cid], depth}
  end

  defp traverse(%{__struct__: _}, _depth) do
    # Skip other structs to avoid recursing into Ecto schemas etc.
    {[], 0}
  end

  defp traverse(data, _depth) when is_map(data) and map_size(data) == 0 do
    {[], 0}
  end

  defp traverse(data, depth) when is_map(data) do
    results =
      Enum.map(data, fn {_key, value} -> traverse(value, depth + 1) end)

    cids = Enum.flat_map(results, fn {c, _d} -> c end)
    max_depth = results |> Enum.map(fn {_c, d} -> d end) |> Enum.max(fn -> 0 end)

    {cids, max_depth}
  end

  defp traverse(data, _depth) when is_list(data) and data == [] do
    {[], 0}
  end

  defp traverse(data, depth) when is_list(data) do
    results = Enum.map(data, fn item -> traverse(item, depth + 1) end)

    cids = Enum.flat_map(results, fn {c, _d} -> c end)
    max_depth = results |> Enum.map(fn {_c, d} -> d end) |> Enum.max(fn -> 0 end)

    {cids, max_depth}
  end

  defp traverse(_data, _depth), do: {[], 0}
end
