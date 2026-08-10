defmodule Excessibility.TelemetryCapture do
  @moduledoc """
  Telemetry-based automatic snapshot capture for LiveView tests.

  Attaches to Phoenix LiveView telemetry events to automatically capture
  snapshots when LiveView events occur, with no test code changes required.
  """

  alias Excessibility.TelemetryCapture.Enrichers.EctoQueries
  alias Excessibility.TelemetryCapture.Formatter
  alias Excessibility.TelemetryCapture.Registry
  alias Excessibility.TelemetryCapture.Timeline

  require Logger

  @ecto_handler_id "excessibility-ecto-capture"
  @ecto_process_key :excessibility_ecto_queries

  @doc """
  Attaches telemetry handlers for automatic snapshot capture.

  Call this before running tests to enable auto-capture.
  """
  def attach do
    # Create ETS table for cross-process snapshot storage
    unless :ets.whereis(:excessibility_snapshots) != :undefined do
      :ets.new(:excessibility_snapshots, [:named_table, :public, :bag])
    end

    :telemetry.attach_many(
      "excessibility-capture",
      [
        [:phoenix, :live_view, :mount, :start],
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_view, :handle_params, :stop],
        [:phoenix, :live_view, :render, :stop]
      ],
      &handle_event/4,
      nil
    )

    attach_ecto()
  end

  @doc """
  Detaches telemetry handlers.
  """
  def detach do
    :telemetry.detach("excessibility-capture")
    :telemetry.detach(@ecto_handler_id)
  rescue
    _ -> :ok
  end

  # Ecto queries fire in the LiveView process while it handles an event, but
  # the enrichment that reads them runs post-hoc from ETS snapshots — so we
  # accumulate queries in the emitting process's dictionary and flush them
  # onto each captured event (issue #147). Without configured repos there is
  # no query event to attach to, so ecto_query_analysis stays dark; say so
  # once instead of silently reporting a green (empty) N+1 section.
  defp attach_ecto do
    case configured_repos() do
      [] ->
        Logger.info(
          "Excessibility: ecto_query_analysis is enabled but no :ecto_repos are configured, " <>
            "so N+1 detection is off. Set `config :excessibility, ecto_repos: [MyApp.Repo]`."
        )

      _repos ->
        :telemetry.attach_many(@ecto_handler_id, ecto_query_events(), &handle_ecto_query/4, nil)
    end

    :ok
  rescue
    # A misconfigured/unstarted repo must never break capture.
    error ->
      Logger.warning("Excessibility: could not attach Ecto query capture: #{inspect(error)}")
      :ok
  end

  defp configured_repos do
    Application.get_env(:excessibility, :ecto_repos, [])
  end

  @doc """
  The Ecto `[..., :query]` telemetry events for the configured `:ecto_repos`.
  """
  def ecto_query_events do
    Enum.map(configured_repos(), &query_event/1)
  end

  # An Ecto repo emits queries at `telemetry_prefix ++ [:query]`. The prefix
  # defaults to the repo module's segments as atoms (MyApp.Repo -> [:my_app,
  # :repo]); a repo that overrides `:telemetry_prefix` is honored.
  defp query_event(repo) do
    prefix =
      case repo_telemetry_prefix(repo) do
        nil -> repo |> Module.split() |> Enum.map(&(&1 |> Macro.underscore() |> String.to_atom()))
        prefix -> prefix
      end

    prefix ++ [:query]
  end

  defp repo_telemetry_prefix(repo) do
    if function_exported?(repo, :config, 0), do: repo.config()[:telemetry_prefix]
  rescue
    _ -> nil
  end

  defp handle_ecto_query(_event, measurements, metadata, _config) do
    record = EctoQueries.build_query_record(measurements, metadata)
    Process.put(@ecto_process_key, [record | Process.get(@ecto_process_key, [])])
  end

  @doc """
  Returns and clears the Ecto queries accumulated in the current process
  since the last flush, oldest first. Called at each captured event so
  queries are attributed to the event that ran them.
  """
  def flush_ecto_queries do
    queries = @ecto_process_key |> Process.get([]) |> Enum.reverse()
    Process.delete(@ecto_process_key)
    queries
  end

  @handle_info_hook_id :excessibility_handle_info

  @doc """
  An **opt-in** `on_mount` hook that records a LiveView's `handle_info`
  messages as timeline events.

  Phoenix LiveView emits telemetry for `mount`/`handle_params`/`handle_event`/
  `render` but not for the message-driven callbacks, so there is no global
  event to attach to (issue #147). This hook is the seam: it uses
  `Phoenix.LiveView.attach_hook/4` on the `:handle_info` stage, which does
  need to be installed per LiveView — so it is opt-in, never forced.

  Wire it wherever you want that coverage — a router `live_session` covers
  every route in the session in one line:

      live_session :default, on_mount: [Excessibility.TelemetryCapture] do
        # ...routes...
      end

  or your web module's `live_view/0` to cover every LiveView. It attaches
  nothing unless telemetry capture is running (`mix excessibility.debug`) and
  the socket is connected, so it is safe to leave wired in all environments.
  Pair it with the (also opt-in) `message_flooding` analyzer.
  """
  def on_mount(_name, _params, _session, socket) do
    if capture_running?() and Phoenix.LiveView.connected?(socket) do
      {:cont, Phoenix.LiveView.attach_hook(socket, @handle_info_hook_id, :handle_info, &handle_info_hook/2)}
    else
      {:cont, socket}
    end
  end

  defp capture_running? do
    System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true"
  end

  # Runs before the LiveView's own handle_info (so assigns are pre-callback,
  # which is fine — message_flooding cares about the event, not the state).
  defp handle_info_hook(message, socket) do
    record_handle_info(message, socket)
    {:cont, socket}
  end

  defp record_handle_info(message, socket) do
    clean_assigns = extract_clean_assigns(socket)
    view_module = extract_view_module(socket, %{})
    store_snapshot("handle_info:#{message_name(message)}", clean_assigns, view_module, %{}, %{}, flush_ecto_queries())
  rescue
    error -> Logger.warning("Excessibility: failed to record handle_info: #{inspect(error)}")
  end

  # A stable, low-cardinality name for grouping: the atom, or a tagged tuple's
  # tag (`{:tick, _}` -> `tick`); anything else collapses to "message".
  defp message_name(message) when is_atom(message), do: message

  defp message_name(message) when is_tuple(message) and tuple_size(message) > 0 do
    case elem(message, 0) do
      tag when is_atom(tag) -> tag
      _ -> "message"
    end
  end

  defp message_name(_message), do: "message"

  @doc """
  Handles telemetry events and captures snapshots.
  """
  # Ecto queries accumulate in the emitting process's dictionary and only clear
  # on flush (at each captured :stop). A test's `setup` seeds run before the
  # LiveView exists, in the same process as the static mount, so those queries
  # would otherwise flush onto `mount`. Resetting the accumulator when the mount
  # begins keeps setup queries out of the first event (issue #151).
  def handle_event([:phoenix, :live_view, :mount, :start], _measurements, _metadata, _config) do
    flush_ecto_queries()
    :ok
  end

  def handle_event([:phoenix, :live_view, :mount, :stop], measurements, metadata, _config) do
    IO.puts("📸 Excessibility: Telemetry mount event fired!")
    capture_snapshot("mount", measurements, metadata)
  end

  def handle_event([:phoenix, :live_view, :handle_event, :stop], measurements, metadata, _config) do
    event_name =
      try do
        get_in(metadata, [:params, "event"]) || "event"
      rescue
        _ -> "event"
      end

    capture_snapshot("handle_event:#{event_name}", measurements, metadata)
  end

  def handle_event([:phoenix, :live_view, :handle_params, :stop], measurements, metadata, _config) do
    capture_snapshot("handle_params", measurements, metadata)
  end

  def handle_event([:phoenix, :live_view, :render, :stop], measurements, metadata, _config) do
    capture_snapshot("render", measurements, metadata)
  end

  defp capture_snapshot(event_type, measurements, metadata) do
    socket = metadata[:socket]

    if socket do
      clean_assigns = extract_clean_assigns(socket)
      view_module = extract_view_module(socket, metadata)
      ecto_queries = flush_ecto_queries()

      store_snapshot(event_type, clean_assigns, view_module, metadata, measurements, ecto_queries)
    else
      Logger.debug("Excessibility: No socket in metadata for #{event_type}")
    end
  rescue
    error ->
      Logger.warning("Excessibility: Failed to capture snapshot for #{event_type}: #{inspect(error)}")
  end

  defp extract_clean_assigns(socket) do
    assigns =
      cond do
        is_struct(socket.assigns) -> Map.from_struct(socket.assigns)
        is_map(socket.assigns) -> socket.assigns
        true -> %{}
      end

    assigns
    |> Map.drop([:flash, :__changed__, :__temp__])
    |> Enum.filter(fn {k, _v} -> !String.starts_with?(to_string(k), "_") end)
    |> Map.new()
  end

  defp extract_view_module(socket, metadata) do
    cond do
      is_struct(socket) && Map.has_key?(socket, :view) -> socket.view
      is_map(metadata) && Map.has_key?(metadata, :view) -> metadata[:view]
      true -> :unknown
    end
  end

  defp store_snapshot(event_type, clean_assigns, view_module, metadata, measurements, ecto_queries) do
    key = {DateTime.utc_now(), :erlang.unique_integer([:monotonic])}

    snapshot = %{
      event_type: event_type,
      assigns: clean_assigns,
      timestamp: DateTime.utc_now(),
      view_module: view_module,
      metadata_keys: Map.keys(metadata),
      measurements: measurements,
      ecto_queries: ecto_queries
    }

    :ets.insert(:excessibility_snapshots, {key, snapshot})

    IO.puts("✅ Captured telemetry snapshot for #{event_type}")
    Logger.debug("Excessibility: Captured snapshot for #{event_type} with assigns: #{inspect(Map.keys(clean_assigns))}")
  end

  @doc """
  Retrieves all captured snapshots and clears the table.
  """
  def get_snapshots do
    case :ets.whereis(:excessibility_snapshots) do
      :undefined ->
        []

      _table ->
        snapshots =
          :excessibility_snapshots
          |> :ets.tab2list()
          |> Enum.map(fn {_key, snapshot} -> snapshot end)
          |> Enum.sort_by(& &1.timestamp, DateTime)

        snapshots
    end
  end

  @doc """
  Clears all captured snapshots.
  """
  def clear_snapshots(_test_name \\ nil) do
    case :ets.whereis(:excessibility_snapshots) do
      :undefined ->
        :ok

      _table ->
        :ets.delete_all_objects(:excessibility_snapshots)
    end
  end

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
    snapshots = get_snapshots()

    if snapshots != [] do
      output_path =
        Application.get_env(
          :excessibility,
          :excessibility_output_path,
          "test/excessibility"
        )

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
      digest =
        Excessibility.Digest.build(timeline,
          ecto_configured?: configured_repos() != [],
          enrichers_run: enricher_names(enrichers),
          plan_capture: plan_capture_mode(),
          fixtures: fixtures()
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
        analyzer_names =
          analyzers_str
          |> String.split(",")
          |> Enum.map(&String.to_atom/1)

        Registry.resolve_enrichers(analyzer_names)
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

  # The configured query-plan capture mode, reported into the digest. Task 10/11
  # will actually run EXPLAIN; here it only surfaces intent. `:explain_analyze`
  # requires an explicit opt-in flag, otherwise it downgrades to `:explain`.
  defp plan_capture_mode do
    case System.get_env("EXCESSIBILITY_QUERY_PLAN") do
      "explain" ->
        :explain

      mode when mode in ["explain_analyze", "analyze"] ->
        if Application.get_env(:excessibility, :query_plan_allow_analyze, false) do
          :explain_analyze
        else
          Logger.warning(
            "Excessibility: EXPLAIN ANALYZE requested but :query_plan_allow_analyze is not " <>
              "enabled; downgrading to EXPLAIN (no data-touching plan capture)."
          )

          :explain
        end

      _ ->
        :disabled
    end
  end

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
