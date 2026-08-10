defmodule Excessibility.Digest do
  @moduledoc """
  Builds the value-free `digest.json` runtime-evidence artifact from an
  in-memory timeline map (the shape `Excessibility.TelemetryCapture.Timeline.build_timeline/3`
  returns).

  The digest is **safe by construction**: every field is built by explicit
  construction from allowlisted inputs. It never copies an assigns map, a raw
  query, params, or bind values. If a field cannot be derived safely it is
  omitted, not guessed. See the design doc's "Privacy allowlist" section.

  Crash-isolated: the whole build is wrapped in `try/rescue`. On failure it
  returns a digest with `capture.status: :failed` and the exception message in
  `capture.warnings`, but never raises.
  """

  alias Excessibility.QueryEvidence

  @schema_version "excessibility.digest/v1"

  @doc """
  Build a value-free digest from an in-memory `timeline` map.

  Options:
  - `:ecto_configured?` (default `false`)
  - `:enrichers_run` (default `[]`)
  - `:plan_capture` (default `:disabled`)
  - `:fixtures` (default `%{}`)
  """
  def build(timeline, opts \\ []) do
    events = Map.get(timeline, :timeline, [])

    %{
      schema: @schema_version,
      capture: capture_block(opts),
      coverage: coverage_block(timeline, events, opts),
      events: build_events(events),
      trajectories: trajectories(events)
    }
  rescue
    e ->
      %{
        schema: @schema_version,
        capture: %{
          status: :failed,
          ecto_configured: Keyword.get(opts, :ecto_configured?, false),
          enrichers_run: Keyword.get(opts, :enrichers_run, []),
          plan_capture: Keyword.get(opts, :plan_capture, :disabled),
          timing: :non_comparable,
          capture_version: capture_version(),
          warnings: [Exception.message(e) | Keyword.get(opts, :warnings, [])]
        },
        coverage: %{tests: [], views: [], callbacks_observed: [], event_sequence: [], fixtures: %{}},
        events: [],
        trajectories: %{}
      }
  end

  defp capture_block(opts) do
    %{
      status: :ok,
      ecto_configured: Keyword.get(opts, :ecto_configured?, false),
      enrichers_run: Keyword.get(opts, :enrichers_run, []),
      plan_capture: Keyword.get(opts, :plan_capture, :disabled),
      timing: :non_comparable,
      capture_version: capture_version(),
      # Plan-capture warnings accumulate in the LiveView process during EXPLAIN
      # and are threaded here via `:warnings` (see TelemetryCapture.write_snapshots/1).
      warnings: Keyword.get(opts, :warnings, [])
    }
  end

  defp coverage_block(timeline, events, opts) do
    callbacks = Enum.map(events, & &1.event)

    %{
      tests: [Map.get(timeline, :test)],
      views: events |> Enum.map(&view_name(&1.view_module)) |> Enum.uniq(),
      callbacks_observed: Enum.uniq(callbacks),
      event_sequence: callbacks,
      fixtures: Keyword.get(opts, :fixtures, %{})
    }
  end

  # Map events in original sequence order, threading each view's previous
  # `assign_sizes` so per-event byte deltas only compare within the same
  # LiveView (a different view's assigns never create a false delta).
  defp build_events(events) do
    {blocks, _prev_by_view} =
      Enum.map_reduce(events, %{}, fn entry, prev_by_view ->
        view = Map.get(entry, :view_module)
        prev_sizes = Map.get(prev_by_view, view, %{})
        block = event_block(entry, prev_sizes)
        {block, Map.put(prev_by_view, view, Map.get(entry, :assign_sizes, %{}))}
      end)

    blocks
  end

  defp event_block(entry, prev_sizes) do
    %{
      sequence: entry.sequence,
      callback: entry.event,
      view: view_name(entry.view_module),
      queries: query_block(entry),
      assigns: assign_block(entry, prev_sizes)
    }
  end

  defp query_block(entry) do
    ecto_queries = Map.get(entry, :ecto_queries, [])

    %{
      count: length(ecto_queries),
      shapes: ecto_queries |> QueryEvidence.shapes() |> maybe_strip_normalized(),
      repeated: QueryEvidence.repeated(ecto_queries, min_repetitions: 3),
      overflow: nil
    }
  end

  defp maybe_strip_normalized(shapes) do
    if include_normalized?() do
      shapes
    else
      Enum.map(shapes, &Map.delete(&1, :normalized))
    end
  end

  defp include_normalized? do
    Application.get_env(:excessibility, :digest_include_normalized_sql, true)
  end

  # Per-event, value-free assign evidence: names + coarse sizes only, never
  # values. `prev_sizes` is the same view's previous-event `assign_sizes` map,
  # used only to derive byte deltas and growth classification.
  defp assign_block(entry, prev_sizes) do
    assign_sizes = Map.get(entry, :assign_sizes, %{})
    list_sizes = Map.get(entry, :list_sizes, %{})

    shapes =
      assign_sizes
      |> Enum.map(fn {name, bytes} ->
        assign_shape(name, bytes, list_sizes, prev_sizes)
      end)
      |> Enum.sort_by(& &1.name)

    %{
      total_term_bytes: Map.get(entry, :total_memory) || sum_bytes(assign_sizes),
      shapes: shapes
    }
  end

  defp assign_shape(name, bytes, list_sizes, prev_sizes) do
    cardinality = Map.get(list_sizes, name)
    prev = Map.get(prev_sizes, name)

    %{
      name: to_string(name),
      # Struct detection is not available from sizes alone, so we only
      # distinguish list (via list_sizes) from everything else, defaulting to
      # "scalar" when we cannot tell.
      kind: if(cardinality != nil, do: "list", else: "scalar"),
      cardinality: cardinality,
      term_bytes: bytes,
      # No enricher emits a bounded per-assign nesting depth today (the `state`
      # enricher's `state_max_depth` is whole-assigns, not per-assign), so 1 is
      # the safe non-fabricated default.
      path_depth: 1,
      delta_bytes: bytes - (prev || 0),
      growth: growth(prev, bytes)
    }
  end

  defp growth(nil, _bytes), do: "new"
  defp growth(prev, bytes) when bytes > prev, do: "increased"
  defp growth(prev, bytes) when bytes < prev, do: "decreased"
  defp growth(_prev, _bytes), do: "stable"

  defp sum_bytes(assign_sizes) do
    assign_sizes |> Map.values() |> Enum.sum()
  end

  # Per-view cross-event assign patterns. Advisory heuristics:
  # - `monotonic_growth`: assign whose term_bytes never shrinks across the
  #   view's events AND strictly increases at least once.
  # - `retained_after_use`: assign that grew at some point and whose final size
  #   is >= its max earlier size (grew then stayed large through the last event).
  defp trajectories(events) do
    events
    |> Enum.group_by(&Map.get(&1, :view_module))
    |> Map.new(fn {view, view_events} ->
      {view_name(view), view_trajectory(view_events)}
    end)
  end

  # Normalize a view module into a clean name for output: live capture emits a
  # module atom, which Jason would render as `"Elixir.MyApp.PageLive"`; the
  # compare consumer joins on the clean form.
  defp view_name(nil), do: nil
  defp view_name(v) when is_binary(v), do: String.replace_prefix(v, "Elixir.", "")
  defp view_name(v) when is_atom(v), do: v |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  defp view_name(v), do: to_string(v)

  defp view_trajectory(view_events) do
    series = byte_series(view_events)

    %{
      monotonic_growth: for({name, bytes} <- series, monotonic_growth?(bytes), do: name),
      retained_after_use: for({name, bytes} <- series, retained_after_use?(bytes), do: name)
    }
  end

  # %{assign_name => [bytes_in_event_order]} across this view's events. The
  # series holds only events where the assign was present, so non-contiguous
  # appearances are treated as adjacent (monotonicity ignores gaps).
  defp byte_series(view_events) do
    view_events
    |> Enum.flat_map(fn entry ->
      entry |> Map.get(:assign_sizes, %{}) |> Enum.map(fn {name, bytes} -> {to_string(name), bytes} end)
    end)
    |> Enum.group_by(fn {name, _bytes} -> name end, fn {_name, bytes} -> bytes end)
  end

  defp monotonic_growth?(bytes) do
    non_decreasing?(bytes) and strictly_increases_once?(bytes)
  end

  defp non_decreasing?(bytes) do
    bytes |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(fn [a, b] -> b >= a end)
  end

  defp strictly_increases_once?(bytes) do
    bytes |> Enum.chunk_every(2, 1, :discard) |> Enum.any?(fn [a, b] -> b > a end)
  end

  defp retained_after_use?(bytes) do
    strictly_increases_once?(bytes) and List.last(bytes) >= Enum.max(bytes)
  end

  defp capture_version do
    :excessibility |> Application.spec(:vsn) |> to_string()
  end
end
