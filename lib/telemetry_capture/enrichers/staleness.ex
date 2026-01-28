defmodule Excessibility.TelemetryCapture.Enrichers.Staleness do
  @moduledoc """
  Enricher that detects stale timestamp fields in assigns.

  Identifies timestamp fields (updated_at, modified_at, synced_at, fetched_at, last_seen_at)
  and flags those that exceed a staleness threshold.

  ## Options

  - `:staleness_threshold` - Age in seconds before data is considered stale (default: 300 = 5 minutes)

  ## Enrichment Fields

  - `stale_data_count` - Number of timestamp fields exceeding threshold
  - `stale_fields` - List of stale field info with `:key` and `:age_seconds`
  - `timestamp_fields` - Total count of timestamp fields found
  - `all_timestamps` - List of all timestamp field info
  """

  @behaviour Excessibility.TelemetryCapture.Enricher

  @default_threshold 300
  @timestamp_patterns ~w(updated_at modified_at synced_at fetched_at last_seen_at inserted_at)a

  @impl true
  def name, do: :staleness

  @impl true
  def enrich(assigns, opts) do
    threshold = Keyword.get(opts, :staleness_threshold, @default_threshold)
    now = DateTime.utc_now()

    timestamps = find_timestamps(assigns, [], now)

    stale =
      timestamps
      |> Enum.filter(fn ts -> ts.age_seconds >= threshold end)
      |> Enum.filter(fn ts -> stale_field?(ts.field_name) end)

    %{
      stale_data_count: length(stale),
      stale_fields: stale,
      timestamp_fields: length(timestamps),
      all_timestamps: timestamps
    }
  end

  defp stale_field?(field_name) do
    # inserted_at is creation time, not relevant for staleness detection
    field_name != :inserted_at
  end

  defp find_timestamps(assigns, path, now) when is_map(assigns) do
    Enum.flat_map(assigns, fn {key, value} ->
      current_path = path ++ [key]

      cond do
        timestamp_field?(key) and is_timestamp?(value) ->
          age = calculate_age(value, now)
          [%{key: path_to_atom(current_path), age_seconds: age, field_name: key}]

        is_map(value) and not struct?(value) ->
          find_timestamps(value, current_path, now)

        is_map(value) and struct?(value) ->
          find_timestamps(Map.from_struct(value), current_path, now)

        true ->
          []
      end
    end)
  end

  defp find_timestamps(_assigns, _path, _now), do: []

  defp timestamp_field?(key) when is_atom(key) do
    key in @timestamp_patterns
  end

  defp timestamp_field?(_), do: false

  defp is_timestamp?(%DateTime{}), do: true
  defp is_timestamp?(%NaiveDateTime{}), do: true
  defp is_timestamp?(_), do: false

  defp calculate_age(%DateTime{} = timestamp, now) do
    DateTime.diff(now, timestamp, :second)
  end

  defp calculate_age(%NaiveDateTime{} = timestamp, now) do
    naive_now = DateTime.to_naive(now)
    NaiveDateTime.diff(naive_now, timestamp, :second)
  end

  defp struct?(%_{} = _value), do: true
  defp struct?(_), do: false

  defp path_to_atom(path) do
    path
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
    |> String.to_atom()
  end
end
