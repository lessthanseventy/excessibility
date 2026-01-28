defmodule Excessibility.TelemetryCapture.Timeline do
  @moduledoc """
  Generates timeline data from telemetry snapshots.

  Extracts key state, computes diffs, and formats timeline entries
  for human and AI consumption.
  """

  alias Excessibility.TelemetryCapture.Diff
  alias Excessibility.TelemetryCapture.Enricher
  alias Excessibility.TelemetryCapture.Filter
  alias Excessibility.TelemetryCapture.Registry

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

  @doc """
  Builds a complete timeline from snapshots.

  Returns a map with:
  - :test - test name
  - :duration_ms - total test duration
  - :timeline - list of timeline entries
  """
  def build_timeline([], test_name) do
    %{
      test: test_name,
      timeline: [],
      duration_ms: 0
    }
  end

  def build_timeline(snapshots, test_name, opts \\ []) do
    first_timestamp = List.first(snapshots).timestamp
    last_timestamp = List.last(snapshots).timestamp
    duration_ms = DateTime.diff(last_timestamp, first_timestamp, :millisecond)

    timeline =
      snapshots
      |> Enum.with_index(1)
      |> Enum.map(fn {snapshot, index} ->
        previous = if index > 1, do: Enum.at(snapshots, index - 2)
        build_timeline_entry(snapshot, previous, index, opts)
      end)

    %{
      test: test_name,
      duration_ms: duration_ms,
      timeline: timeline
    }
  end

  @doc """
  Builds a single timeline entry from a snapshot and its predecessor.
  """
  def build_timeline_entry(snapshot, previous, sequence, opts \\ []) do
    filtered_assigns = Filter.filter_assigns(snapshot.assigns, opts)

    key_state =
      extract_key_state(filtered_assigns, opts[:highlight_fields] || @default_highlight_fields)

    previous_assigns =
      if previous do
        Filter.filter_assigns(previous.assigns, opts)
      end

    diff = Diff.compute_diff(filtered_assigns, previous_assigns)
    changes = Diff.extract_changes(diff)

    duration_since_previous =
      if previous do
        DateTime.diff(snapshot.timestamp, previous.timestamp, :millisecond)
      end

    # NEW: Run enrichers
    enrichments = run_enrichers(filtered_assigns, snapshot, opts)

    Map.merge(
      %{
        sequence: sequence,
        event: snapshot.event_type,
        timestamp: snapshot.timestamp,
        view_module: snapshot.view_module,
        key_state: key_state,
        changes: changes,
        duration_since_previous_ms: duration_since_previous
      },
      enrichments
    )
  end

  # Run selected enrichers on assigns
  defp run_enrichers(assigns, snapshot, opts) do
    requested_enrichers = Keyword.get(opts, :enrichers, :all)
    quick? = Keyword.get(opts, :quick, false)

    enrichers =
      case requested_enrichers do
        :all ->
          Registry.discover_enrichers()

        names when is_list(names) ->
          names
          |> Enum.map(&Registry.get_enricher/1)
          |> Enum.reject(&is_nil/1)
      end

    # Filter out expensive enrichers when quick mode is enabled
    enrichers =
      if quick? do
        Enum.reject(enrichers, fn enricher ->
          Enricher.get_cost(enricher) == :expensive
        end)
      else
        enrichers
      end

    # Pass measurements through opts for enrichers that need them
    measurements = Map.get(snapshot, :measurements, %{})
    enricher_opts = Keyword.put(opts, :measurements, measurements)

    Enum.reduce(enrichers, %{}, fn enricher, acc ->
      enrichment = enricher.enrich(assigns, enricher_opts)
      Map.merge(acc, enrichment)
    end)
  end
end
