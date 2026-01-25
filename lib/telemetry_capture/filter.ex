defmodule Excessibility.TelemetryCapture.Filter do
  @moduledoc """
  Filters noise from telemetry snapshot assigns.

  Removes Ecto metadata, Phoenix internals, and other noise
  to improve signal-to-noise ratio for debugging.
  """

  @doc """
  Removes Ecto-related metadata from assigns.

  Filters out:
  - `__meta__` fields
  - `NotLoaded` associations
  """
  def filter_ecto_metadata(assigns) when is_map(assigns) do
    Enum.reduce(assigns, %{}, fn {key, value}, acc ->
      cond do
        key == :__meta__ -> acc
        is_struct(value) and value.__struct__ == Ecto.Association.NotLoaded -> acc
        is_map(value) and not is_struct(value) -> Map.put(acc, key, filter_ecto_metadata(value))
        is_list(value) -> Map.put(acc, key, Enum.map(value, &filter_ecto_metadata/1))
        true -> Map.put(acc, key, value)
      end
    end)

    # Skip __meta__ fields

    # Skip NotLoaded associations

    # Recursively filter maps

    # Recursively filter lists

    # Keep everything else
  end

  def filter_ecto_metadata(value) when is_list(value) do
    Enum.map(value, &filter_ecto_metadata/1)
  end

  def filter_ecto_metadata(value), do: value
end
