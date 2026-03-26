defmodule Excessibility.TelemetryCapture.Enrichers.AssignSizes do
  @moduledoc """
  Enriches timeline events with per-assign byte size information.

  Replaces the old Memory enricher. Tracks individual assign sizes
  plus total memory, enabling the assign_diff analyzer to detect
  large assigns that get re-diffed frequently.

  ## Example Output

      %{
        assign_sizes: %{current_user: 12400, products: 8200, filter: 120},
        total_memory: 20720,
        largest_assign: {:current_user, 12400}
      }
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  @skip_keys [:flash, :__changed__, :__temp__]

  def name, do: :assign_sizes
  def cost, do: :expensive

  def enrich(assigns, _opts) do
    sizes =
      assigns
      |> Enum.reject(fn {key, _} -> key in @skip_keys or private_key?(key) end)
      |> Map.new(fn {key, value} -> {key, byte_size(:erlang.term_to_binary(value))} end)

    total = sizes |> Map.values() |> Enum.sum()

    largest =
      if map_size(sizes) > 0 do
        Enum.max_by(sizes, fn {_k, v} -> v end)
      end

    %{
      assign_sizes: sizes,
      total_memory: total,
      largest_assign: largest
    }
  end

  defp private_key?(key) do
    key |> Atom.to_string() |> String.starts_with?("_")
  end
end
