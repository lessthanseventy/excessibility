defmodule Excessibility.TelemetryCapture do
  @moduledoc """
  Telemetry-based automatic snapshot capture for LiveView tests.

  Attaches to Phoenix LiveView telemetry events to automatically capture
  snapshots when LiveView events occur, with no test code changes required.
  """

  alias Excessibility.TelemetryCapture.EctoCapture
  alias Excessibility.TelemetryCapture.SnapshotStore
  alias Excessibility.TelemetryCapture.Writer

  require Logger

  @ecto_handler_id "excessibility-ecto-capture"
  @suppress_key :excessibility_capture_suppressed

  @doc """
  Attaches telemetry handlers for automatic snapshot capture.

  Call this before running tests to enable auto-capture.
  """
  def attach do
    # Own the cross-process snapshot ETS table in a dedicated, long-lived process
    # so its lifetime is not tied to whichever test process happened to call
    # attach/0 first — a test finishing must not delete the table out from under
    # another test still writing to it (flaky ETS race).
    SnapshotStore.ensure_started()

    :telemetry.attach_many(
      "excessibility-capture",
      [
        [:phoenix, :live_view, :mount, :start],
        [:phoenix, :live_view, :mount, :stop],
        [:phoenix, :live_view, :handle_event, :stop],
        [:phoenix, :live_component, :handle_event, :stop],
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
    :ok
  end

  # Ecto queries fire in the LiveView process while it handles an event, but
  # the enrichment that reads them runs post-hoc from ETS snapshots — so we
  # accumulate queries in the emitting process's dictionary and flush them
  # onto each captured event. Without configured repos there is
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

  @doc false
  @spec configured_repos() :: [module()]
  def configured_repos do
    Application.get_env(:excessibility, :ecto_repos, [])
  end

  @doc false
  defdelegate ecto_query_events, to: EctoCapture

  @doc false
  defdelegate handle_ecto_query(arg1, measurements, metadata, arg4), to: EctoCapture

  @doc false
  defdelegate drain_plan_warnings, to: EctoCapture

  @doc false
  defdelegate flush_ecto_queries, to: EctoCapture

  @handle_info_hook_id :excessibility_handle_info

  @doc """
  An **opt-in** `on_mount` hook that records a LiveView's `handle_info`
  messages as timeline events.

  Phoenix LiveView emits telemetry for `mount`/`handle_params`/`handle_event`/
  `render` but not for the message-driven callbacks, so there is no global
  event to attach to. This hook is the seam: it uses
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
    store_snapshot("handle_info:#{message_name(message)}", socket, %{}, %{})
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
  # begins keeps setup queries out of the first event.
  def handle_event([:phoenix, :live_view, :mount, :start], _measurements, _metadata, _config) do
    flush_ecto_queries()
    :ok
  end

  def handle_event([:phoenix, :live_view, :mount, :stop], measurements, metadata, _config) do
    capture_snapshot("mount", measurements, metadata)
  end

  def handle_event([:phoenix, kind, :handle_event, :stop], measurements, metadata, _config)
      when kind in [:live_view, :live_component] do
    capture_snapshot("handle_event:#{Map.get(metadata, :event, "event")}", measurements, metadata)
  end

  def handle_event([:phoenix, :live_view, :handle_params, :stop], measurements, metadata, _config) do
    capture_snapshot("handle_params", measurements, metadata)
  end

  def handle_event([:phoenix, :live_view, :render, :stop], measurements, metadata, _config) do
    capture_snapshot("render", measurements, metadata)
  end

  defp capture_snapshot(event_type, measurements, metadata) do
    socket = metadata[:socket]

    cond do
      capture_suppressed?() -> :ok
      socket -> store_snapshot(event_type, socket, metadata, measurements)
      true -> Logger.debug("Excessibility: No socket in metadata for #{event_type}")
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
    |> Enum.filter(fn {k, _v} -> not String.starts_with?(to_string(k), "_") end)
    |> Map.new()
  end

  defp extract_view_module(socket, metadata) do
    cond do
      is_struct(socket) and Map.has_key?(socket, :view) -> socket.view
      is_map(metadata) and Map.has_key?(metadata, :view) -> metadata.view
      true -> :unknown
    end
  end

  @doc """
  Marks the timeline with an `html_snapshot/2` call, so a timeline event can be
  matched to the snapshot file `name` taken at that point. Does nothing unless
  telemetry capture is running.
  """
  @spec record_html_snapshot(String.t()) :: :ok
  def record_html_snapshot(name) do
    if capture_running?() and :ets.whereis(:excessibility_snapshots) != :undefined do
      insert_snapshot(%{
        event_type: "snapshot",
        snapshot: name,
        assigns: %{},
        timestamp: DateTime.utc_now(),
        view_module: nil,
        component: nil
      })
    end

    :ok
  end

  @doc """
  Runs `fun` with capture suspended in this process and returns its result.

  The `<head>` render of a snapshot mounts whatever LiveView `:head_render_path`
  routes to; those events, and the queries they fire, are not part of the test.
  """
  @spec without_capture((-> result)) :: result when result: var
  def without_capture(fun) do
    previous = Process.put(@suppress_key, true)

    try do
      fun.()
    after
      Process.put(@suppress_key, previous || false)
    end
  end

  @doc false
  @spec capture_suppressed?() :: boolean()
  def capture_suppressed?, do: Process.get(@suppress_key, false)

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

  @doc false
  defdelegate write_snapshots(module, test_name), to: Writer

  # The configured query-plan capture mode, reported into the digest. Task 10/11
  # will actually run EXPLAIN; here it only surfaces intent. `:explain_analyze`
  # requires an explicit opt-in flag, otherwise it downgrades to `:explain`.
  @doc false
  @spec plan_capture_mode() :: :explain | :explain_analyze | nil
  def plan_capture_mode do
    case System.get_env("EXCESSIBILITY_QUERY_PLAN") do
      "explain" ->
        :explain

      mode when mode in ["explain_analyze", "analyze"] ->
        if Application.get_env(:excessibility, :query_plan_allow_analyze, false) do
          :explain_analyze
        else
          EctoCapture.warn_analyze_downgrade_once()
          :explain
        end

      _ ->
        :disabled
    end
  end

  @doc false
  defdelegate reset_analyze_downgrade_warning, to: EctoCapture

  defp store_snapshot(event_type, socket, metadata, measurements) do
    clean_assigns = extract_clean_assigns(socket)

    insert_snapshot(%{
      event_type: event_type,
      assigns: clean_assigns,
      timestamp: DateTime.utc_now(),
      view_module: extract_view_module(socket, metadata),
      component: Map.get(metadata, :component),
      component_id: component_id(socket, metadata),
      connected?: is_pid(Map.get(socket, :transport_pid)),
      metadata_keys: Map.keys(metadata),
      measurements: measurements,
      ecto_queries: flush_ecto_queries(),
      plan_warnings: drain_plan_warnings()
    })

    Logger.debug("Excessibility: Captured snapshot for #{event_type} with assigns: #{inspect(Map.keys(clean_assigns))}")
  end

  defp component_id(socket, %{component: _component}), do: Map.get(socket.assigns, :id)
  defp component_id(_socket, _metadata), do: nil

  defp insert_snapshot(snapshot) do
    :ets.insert(:excessibility_snapshots, {{snapshot.timestamp, :erlang.unique_integer([:monotonic])}, snapshot})
  end
end
