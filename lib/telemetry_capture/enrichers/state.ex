defmodule Excessibility.TelemetryCapture.Enrichers.State do
  @moduledoc """
  Enriches timeline events with state structure information.

  Tracks:
  - Keys present in assigns
  - Total key count
  - Maximum nesting depth

  ## Usage

  Runs automatically during timeline building. Adds state metadata
  to each timeline event.

  ## Example Output

      %{
        sequence: 3,
        event: "handle_event:filter",
        state_keys: [:user_id, :products, :filters],
        state_key_count: 3,
        state_max_depth: 4
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :state

  def enrich(assigns, _opts) do
    keys = Map.keys(assigns)
    depth = calculate_max_depth(assigns)

    %{
      state_keys: keys,
      state_key_count: length(keys),
      state_max_depth: depth
    }
  end

  defp calculate_max_depth(value) when is_struct(value) do
    value
    |> Map.from_struct()
    |> calculate_max_depth()
  end

  defp calculate_max_depth(value) when is_map(value) and map_size(value) == 0, do: 0

  defp calculate_max_depth(value) when is_map(value) do
    value
    |> Map.reject(fn {key, _} -> key in [:__meta__, :__struct__] end)
    |> Enum.map(fn {_key, val} -> calculate_max_depth(val) end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp calculate_max_depth(value) when is_list(value) and value == [], do: 0

  defp calculate_max_depth(value) when is_list(value) do
    value
    |> Enum.map(&calculate_max_depth/1)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp calculate_max_depth(_value), do: 0
end
