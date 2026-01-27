defmodule Excessibility.TelemetryCapture.Enrichers.Query do
  @behaviour Excessibility.TelemetryCapture.Enricher

  @moduledoc """
  Enriches timeline events with query/database information.

  Counts:
  - Total Ecto records loaded in assigns
  - NotLoaded associations (potential N+1 indicators)

  ## Usage

  Runs automatically during timeline building. Adds query metrics
  to each timeline event.

  ## Example Output

      %{
        sequence: 3,
        event: "handle_event:filter",
        query_records_loaded: 47,
        query_not_loaded_count: 12
      }
  """

  def name, do: :query

  def enrich(assigns, _opts) do
    {records_loaded, not_loaded_count} = count_queries(assigns)

    %{
      query_records_loaded: records_loaded,
      query_not_loaded_count: not_loaded_count
    }
  end

  defp count_queries(assigns) do
    count_queries_recursive(assigns, {0, 0})
  end

  defp count_queries_recursive(value, {records, not_loaded}) when is_struct(value) do
    cond do
      # Check if it's a NotLoaded association
      value.__struct__ == Ecto.Association.NotLoaded ->
        {records, not_loaded + 1}

      # It's an Ecto struct - count it and recurse into its fields
      is_ecto_struct?(value) ->
        value
        |> Map.from_struct()
        |> count_queries_recursive({records + 1, not_loaded})

      # Other struct - just recurse
      true ->
        value
        |> Map.from_struct()
        |> count_queries_recursive({records, not_loaded})
    end
  end

  defp count_queries_recursive(value, acc) when is_map(value) do
    Enum.reduce(value, acc, fn {_key, val}, acc_inner ->
      count_queries_recursive(val, acc_inner)
    end)
  end

  defp count_queries_recursive(value, acc) when is_list(value) do
    Enum.reduce(value, acc, fn item, acc_inner ->
      count_queries_recursive(item, acc_inner)
    end)
  end

  defp count_queries_recursive(_value, acc), do: acc

  # Check if a struct is an Ecto schema
  # Ecto schemas have __meta__ field or are database-backed
  defp is_ecto_struct?(struct) do
    Map.has_key?(struct, :__meta__) or
      (Map.has_key?(struct, :__struct__) and
         not (struct.__struct__ in [Ecto.Association.NotLoaded]))
  end
end
