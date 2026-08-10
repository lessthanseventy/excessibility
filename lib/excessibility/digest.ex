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
      events: Enum.map(events, &event_block/1)
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
          warnings: [Exception.message(e)]
        },
        events: []
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
      warnings: []
    }
  end

  defp coverage_block(timeline, events, opts) do
    callbacks = Enum.map(events, & &1.event)

    %{
      tests: [Map.get(timeline, :test)],
      views: events |> Enum.map(& &1.view_module) |> Enum.uniq(),
      callbacks_observed: Enum.uniq(callbacks),
      event_sequence: callbacks,
      fixtures: Keyword.get(opts, :fixtures, %{})
    }
  end

  defp event_block(entry) do
    %{
      sequence: entry.sequence,
      callback: entry.event,
      view: entry.view_module,
      queries: query_block(entry),
      assigns: assign_block(entry)
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

  # TODO(#154): Task 6 — real assign shapes/trajectories. Stub for now.
  defp assign_block(entry) do
    %{total_term_bytes: Map.get(entry, :total_memory, 0), shapes: []}
  end

  defp capture_version do
    :excessibility |> Application.spec(:vsn) |> to_string()
  end
end
