defmodule Excessibility.TelemetryCapture.Diff do
  @moduledoc """
  Computes differences between sequential telemetry snapshots.

  Identifies added, changed, and removed assigns to highlight
  what actually changed between LiveView events.
  """

  @doc """
  Computes the diff between current and previous assigns.

  Returns nil if previous is nil (first snapshot).
  Returns a map with :added, :changed, :removed keys.
  """
  def compute_diff(_current, nil), do: nil

  def compute_diff(current, previous) when is_map(current) and is_map(previous) do
    current_keys = MapSet.new(Map.keys(current))
    previous_keys = MapSet.new(Map.keys(previous))

    added_keys = MapSet.difference(current_keys, previous_keys)
    removed_keys = MapSet.difference(previous_keys, current_keys)
    common_keys = MapSet.intersection(current_keys, previous_keys)

    added =
      Map.new(added_keys, &{&1, Map.get(current, &1)})

    changed =
      Enum.reduce(common_keys, %{}, fn key, acc ->
        current_val = Map.get(current, key)
        previous_val = Map.get(previous, key)

        cond do
          current_val == previous_val ->
            acc

          is_map(current_val) and is_map(previous_val) and not is_struct(current_val) and not is_struct(previous_val) ->
            detect_nested_changes(to_string(key), current_val, previous_val, acc)

          true ->
            Map.put(acc, to_string(key), {previous_val, current_val})
        end
      end)

    %{
      added: added,
      changed: changed,
      removed: Enum.to_list(removed_keys)
    }
  end

  @doc """
  Extracts changes from a diff into a simple map format.

  Converts added/changed/removed into a flat map of field => {old, new} tuples.
  """
  def extract_changes(nil), do: nil

  def extract_changes(%{added: added, changed: changed, removed: _removed}) do
    added_changes =
      Map.new(added, fn {key, val} -> {to_string(key), {nil, val}} end)

    Map.merge(added_changes, changed)
  end

  # Private helpers

  defp detect_nested_changes(path, current, previous, acc)
       when is_map(current) and is_map(previous) and not is_struct(current) and not is_struct(previous) do
    Enum.reduce(current, acc, fn {key, val}, nested_acc ->
      prev_val = Map.get(previous, key)
      nested_path = "#{path}.#{key}"

      cond do
        prev_val == nil -> Map.put(nested_acc, nested_path, {nil, val})
        val != prev_val -> detect_nested_changes(nested_path, val, prev_val, nested_acc)
        true -> nested_acc
      end
    end)
  end

  defp detect_nested_changes(path, current, previous, acc) do
    Map.put(acc, path, {previous, current})
  end
end
