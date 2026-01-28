defmodule Excessibility.TelemetryCapture.Enrichers.CollectionSize do
  @moduledoc """
  Enriches timeline events with collection size information.

  Tracks:
  - Individual list sizes (with paths)
  - Maximum list size
  - Total list items count

  ## Usage

  Runs automatically during timeline building. Adds collection metrics
  to each timeline event.

  ## Example Output

      %{
        sequence: 3,
        event: "handle_event:filter",
        list_sizes: %{products: 50, "cart.items": 12},
        max_list_size: 50,
        total_list_items: 62
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :collection_size
  def cost, do: :expensive

  def enrich(assigns, _opts) do
    {list_sizes, total_items} = count_lists(assigns, [])

    max_size =
      if map_size(list_sizes) > 0 do
        list_sizes |> Map.values() |> Enum.max()
      else
        0
      end

    %{
      list_sizes: list_sizes,
      max_list_size: max_size,
      total_list_items: total_items
    }
  end

  defp count_lists(value, path) when is_struct(value) do
    value
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__struct__])
    |> count_lists(path)
  end

  defp count_lists(value, path) when is_map(value) do
    Enum.reduce(value, {%{}, 0}, fn {key, val}, {sizes_acc, total_acc} ->
      new_path = path ++ [key]
      {val_sizes, val_total} = count_lists(val, new_path)

      {
        Map.merge(sizes_acc, val_sizes),
        total_acc + val_total
      }
    end)
  end

  defp count_lists(value, path) when is_list(value) do
    # Count this list
    list_size = length(value)
    path_key = build_path_key(path)

    # Also recurse into list items
    {nested_sizes, nested_total} =
      value
      |> Enum.with_index()
      |> Enum.reduce({%{}, 0}, fn {item, index}, {sizes_acc, total_acc} ->
        item_path = path ++ [index]
        {item_sizes, item_total} = count_lists(item, item_path)

        {
          Map.merge(sizes_acc, item_sizes),
          total_acc + item_total
        }
      end)

    sizes = Map.put(nested_sizes, path_key, list_size)
    total = list_size + nested_total

    {sizes, total}
  end

  defp count_lists(_value, _path), do: {%{}, 0}

  defp build_path_key([]), do: :root

  defp build_path_key(path) do
    path
    |> Enum.map_join(".", fn
      key when is_atom(key) -> Atom.to_string(key)
      key when is_integer(key) -> "[#{key}]"
      key -> to_string(key)
    end)
    |> String.replace(".[", "[")
    |> String.to_atom()
  end
end
