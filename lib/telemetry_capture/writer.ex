defmodule Excessibility.TelemetryCapture.Writer do
  @moduledoc """
  Writes a capture run's snapshots to `timeline.json` and the value-free
  `digest.json` for `Excessibility.TelemetryCapture`.
  """

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.Formatter
  alias Excessibility.TelemetryCapture.Registry
  alias Excessibility.TelemetryCapture.Timeline

  require Logger

  @doc """
  Writes captured snapshots to timeline.json.

  Note: HTML snapshot files are NOT generated from telemetry capture.
  For real accessibility testing, use `html_snapshot(view)` in your tests
  to capture actual rendered HTML.

  Runs in the `on_exit` installed by `use Excessibility`, so a failure
  here is logged rather than raised — instrumentation must not fail the
  test it observes.
  """
  def write_snapshots(test_name) do
    snapshots = TelemetryCapture.get_snapshots()

    if snapshots != [] do
      output_path = Excessibility.Paths.output_path()

      File.mkdir_p!(output_path)

      # Generate and write timeline.json with selective enrichment
      enrichers = resolve_enrichers_from_env()
      timeline = Timeline.build_timeline(snapshots, test_name, enrichers: enrichers)
      timeline_json = Formatter.format_json(timeline)
      timeline_path = Path.join(output_path, "timeline.json")
      File.write!(timeline_path, timeline_json)

      IO.puts("📊 Excessibility: Wrote timeline.json with #{length(snapshots)} events")

      # Build and write the value-free digest.json from the same in-memory
      # timeline. Digest.build is crash-isolated; the outer rescue is a backstop.
      #
      # Plan-capture warnings are accumulated (drain_plan_warnings/0) in the
      # LiveView process that ran the EXPLAIN, then stashed on each ETS snapshot
      # at capture time (store_snapshot/7). Here we aggregate them across all
      # snapshots and thread them into the digest's `capture.warnings`.
      effective_plan = TelemetryCapture.plan_capture_mode()
      requested_plan = requested_plan_mode()

      digest =
        Excessibility.Digest.build(timeline,
          ecto_configured?: TelemetryCapture.configured_repos() != [],
          enrichers_run: enricher_names(enrichers),
          plan_capture: effective_plan,
          fixtures: fixtures(),
          warnings:
            aggregate_plan_warnings(snapshots) ++
              analyze_downgrade_digest_warnings(requested_plan, effective_plan)
        )

      File.write!(Path.join(output_path, "digest.json"), Formatter.format_json(digest))
      IO.puts("🔒 Excessibility: Wrote digest.json (value-free)")
    end
  rescue
    error ->
      Logger.warning(
        "Excessibility: Failed to write timeline for #{inspect(test_name)}: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      :ok
  end

  # Flatten every snapshot's stashed plan-capture warnings (in event order) into
  # a single list for the digest. Snapshots predating this field simply carry no
  # `:plan_warnings` key and contribute nothing.
  defp aggregate_plan_warnings(snapshots) do
    Enum.flat_map(snapshots, &Map.get(&1, :plan_warnings, []))
  end

  # Resolve which enrichers to run based on EXCESSIBILITY_ANALYZERS env var
  defp resolve_enrichers_from_env do
    case System.get_env("EXCESSIBILITY_ANALYZERS") do
      nil ->
        # No analyzer selection - use all enrichers
        :all

      "" ->
        # Empty string means no analyzers - use no enrichers
        []

      analyzers_str ->
        # Parse analyzer names and resolve their enrichers
        case Registry.analyzer_names_from_string(analyzers_str) do
          {:ok, analyzer_names} ->
            Registry.resolve_enrichers(analyzer_names)

          {:error, unknown} ->
            raise ArgumentError,
                  "EXCESSIBILITY_ANALYZERS names unknown analyzers: #{Enum.join(unknown, ", ")}"
        end
    end
  end

  # Resolve the `enrichers` value passed to `build_timeline` (`:all`, `[]`, or a
  # list of enricher names/modules) into a plain list of enricher name atoms for
  # the digest's `capture.enrichers_run`. Defensive: never raises.
  defp enricher_names(:all) do
    Enum.map(Registry.discover_enrichers(), & &1.name())
  rescue
    _ -> []
  end

  defp enricher_names(enrichers) when is_list(enrichers) do
    Enum.map(enrichers, &enricher_name/1)
  rescue
    _ -> []
  end

  defp enricher_names(_), do: []

  # A name atom (e.g. `:ecto_queries`) passes through; an enricher module is
  # resolved to its `name/0`.
  defp enricher_name(mod) when is_atom(mod) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, :name, 0) do
      mod.name()
    else
      mod
    end
  end

  defp enricher_name(other), do: other

  # The plan mode the run *asked* for, before the ANALYZE gate is applied. Kept
  # distinct from the effective mode so the digest can surface requested vs
  # effective (a downgrade) rather than silently reporting only `:explain`.
  defp requested_plan_mode do
    case System.get_env("EXCESSIBILITY_QUERY_PLAN") do
      "explain" -> :explain
      mode when mode in ["explain_analyze", "analyze"] -> :explain_analyze
      _ -> :disabled
    end
  end

  # A single value-free warning describing the ANALYZE→EXPLAIN downgrade, added
  # to the digest's `capture.warnings` exactly once per run (write_snapshots/1
  # runs once per capture). This carries the requested/effective modes into the
  # value-free capture metadata.
  defp analyze_downgrade_digest_warnings(:explain_analyze, :explain) do
    [
      "EXPLAIN ANALYZE requested but :query_plan_allow_analyze is not enabled; " <>
        "effective plan mode downgraded to EXPLAIN (no data-touching plan capture)"
    ]
  end

  defp analyze_downgrade_digest_warnings(_requested, _effective), do: []

  # Fixtures for the digest coverage block, from both channels: the
  # `EXCESSIBILITY_FIXTURES` env JSON (precedence, string keys kept) falls back
  # to `config :excessibility, :fixtures`, then `%{}`. Never crashes the run.
  defp fixtures do
    case System.get_env("EXCESSIBILITY_FIXTURES") do
      blank when blank in [nil, ""] ->
        config_fixtures()

      json ->
        case Jason.decode(json) do
          {:ok, map} when is_map(map) ->
            map

          _ ->
            Logger.warning("Excessibility: EXCESSIBILITY_FIXTURES is not a JSON object; ignoring it.")

            config_fixtures()
        end
    end
  end

  defp config_fixtures do
    Application.get_env(:excessibility, :fixtures, %{})
  end
end
