defmodule Excessibility.TelemetryCapture.Formatter do
  @moduledoc """
  Formats telemetry timeline data for different output formats.

  Supports:
  - JSON (machine-readable)
  - Markdown (human/AI-readable)
  - Package (directory with multiple files)
  """

  @doc """
  Formats timeline as JSON.

  Converts tuples to lists and structs to maps for JSON compatibility.
  Removes Ecto `__meta__` fields from converted structs.
  """
  def format_json(timeline) do
    timeline
    |> prepare_for_json()
    |> Jason.encode!(pretty: true)
  end

  # Handle tuples first (convert to lists for JSON)
  defp prepare_for_json(data) when is_tuple(data) do
    data |> Tuple.to_list() |> prepare_for_json()
  end

  # Handle lists
  defp prepare_for_json(data) when is_list(data) do
    Enum.map(data, &prepare_for_json/1)
  end

  # Handle structs (convert to maps for JSON encoding)
  defp prepare_for_json(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> prepare_for_json()
  end

  # Handle regular maps
  defp prepare_for_json(data) when is_map(data) do
    Map.new(data, fn {k, v} -> {k, prepare_for_json(v)} end)
  end

  # Handle functions - convert to string representation (defense-in-depth)
  defp prepare_for_json(data) when is_function(data) do
    info = Function.info(data)
    "#Function<#{info[:name]}/#{info[:arity]}>"
  end

  # Handle primitives
  defp prepare_for_json(data), do: data

  @doc """
  Formats timeline as markdown report.

  Includes:
  - Summary header
  - Timeline table
  - Detailed change sections
  - Optional full snapshots (if snapshots provided)
  """
  def format_markdown(timeline, _snapshots) do
    """
    # Test Debug Report: #{timeline.test}

    **Duration:** #{timeline.duration_ms}ms

    ## Event Timeline

    #{build_timeline_table(timeline.timeline)}

    ## Detailed Changes

    #{build_detailed_changes(timeline.timeline)}
    """
  end

  defp build_timeline_table(entries) do
    header = "| # | Time | Event | Key Changes |\n|---|------|-------|-------------|"

    rows =
      Enum.map_join(entries, "\n", fn entry ->
        time = "+#{entry.duration_since_previous_ms || 0}ms"
        changes = format_key_changes(entry.changes)
        "| #{entry.sequence} | #{time} | #{entry.event} | #{changes} |"
      end)

    header <> "\n" <> rows
  end

  defp format_key_changes(nil), do: ""

  defp format_key_changes(changes) when map_size(changes) == 0, do: ""

  defp format_key_changes(changes) do
    changes
    |> Enum.take(3)
    |> Enum.map_join(", ", fn {field, value} ->
      {old, new} = normalize_change_value(value)
      "#{field}: #{inspect(old)}→#{inspect(new)}"
    end)
  end

  defp build_detailed_changes(entries) do
    entries
    |> Enum.filter(fn entry -> entry.changes != nil and map_size(entry.changes) > 0 end)
    |> Enum.map_join("\n\n---\n\n", &format_detailed_change/1)
  end

  defp format_detailed_change(entry) do
    """
    ### Event #{entry.sequence}: #{entry.event} (+#{entry.duration_since_previous_ms || 0}ms)

    **State Changes:**
    #{format_change_list(entry.changes)}

    **Key State:**
    ```elixir
    #{inspect(entry.key_state, pretty: true)}
    ```
    """
  end

  defp format_change_list(changes) do
    Enum.map_join(changes, "\n", fn {field, value} ->
      {old, new} = normalize_change_value(value)
      "- `#{field}`: #{inspect(old)} → #{inspect(new)}"
    end)
  end

  # Handle both tuple format (in-memory) and list format (from JSON)
  defp normalize_change_value({old, new}), do: {old, new}
  defp normalize_change_value([old, new]), do: {old, new}
end
