defmodule Excessibility.TelemetryCapture.Timeline do
  @moduledoc """
  Generates timeline data from telemetry snapshots.

  Extracts key state, computes diffs, and formats timeline entries
  for human and AI consumption.
  """

  @default_highlight_fields [:current_user, :live_action, :errors, :form]
  @small_value_threshold 100

  @doc """
  Extracts key state from assigns for timeline display.

  Includes:
  - Highlighted fields (from config)
  - Small primitive values (< #{@small_value_threshold} chars)
  - List counts (products: [3 items] -> products_count: 3)
  - Auto-detected important fields (status, action, etc.)
  """
  def extract_key_state(assigns, highlight_fields \\ @default_highlight_fields) do
    using_defaults? = highlight_fields == @default_highlight_fields

    Enum.reduce(assigns, %{}, fn {key, value}, acc ->
      cond do
        key in highlight_fields -> Map.put(acc, key, value)
        is_list(value) -> Map.put(acc, :"#{key}_count", length(value))
        using_defaults? and small_value?(value) -> Map.put(acc, key, value)
        true -> acc
      end
    end)

    # Always include highlighted fields as-is

    # Convert non-highlighted lists to counts

    # Include small primitives only when using default fields

    # Skip everything else
  end

  defp small_value?(value) when is_integer(value), do: true
  defp small_value?(value) when is_atom(value), do: true
  defp small_value?(value) when is_boolean(value), do: true

  defp small_value?(value) when is_binary(value) do
    byte_size(value) <= @small_value_threshold
  end

  defp small_value?(_), do: false
end
