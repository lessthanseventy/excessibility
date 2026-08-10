defmodule Excessibility.TelemetryCapture.AttributionTest do
  @moduledoc """
  Regression locks on the TEMPORAL callback-attribution boundaries.

  Query attribution is buffered and temporal: Ecto queries accumulate in the
  emitting process's dictionary and are attributed to the NEXT captured `:stop`
  event (which calls `flush_ecto_queries/0` and stamps them onto that event's
  snapshot). `mount.start` additionally flushes/discards the accumulator so a
  test's pre-mount `setup` seeds never bleed onto `mount` (issue #151).

  These tests drive the telemetry events IN ORDER within a single process and
  assert, for each scenario, that a query lands on the EXPECTED callback's
  snapshot `ecto_queries` AND nowhere else — so buffered process-local
  telemetry cannot silently move query work to the wrong callback.

  How each event is driven:
  - LiveView lifecycle events are driven by calling `handle_event/4` directly
    (matching `telemetry_capture_integration_test.exs`). Driving them through
    real `:telemetry.execute/3` also fans out to Phoenix's own
    `LiveView.Logger` handler, which crashes on synthetic metadata and gets
    globally detached — collateral that would bleed into other tests. Direct
    calls exercise the exact clauses under test without that side effect.
  - Ecto queries are driven by calling `handle_ecto_query/4` directly (matching
    `telemetry_capture_plan_test.exs`): deterministic and independent of whether
    `:ecto_repos` is configured, since attach only wires the Ecto handler when
    repos are configured. `plan_capture_mode/0` is disabled by default, so no
    EXPLAIN runs.
  """
  # Not async: the `:excessibility_snapshots` ETS table is a shared, named,
  # public table. Process-dict query buffering is naturally per-test (ExUnit
  # runs each test in its own process).
  use ExUnit.Case

  alias Excessibility.TelemetryCapture

  @ecto_key :excessibility_ecto_queries

  defmodule TestLive do
    @moduledoc false
  end

  setup do
    # Start from a clean slate: no buffered queries, no stale ETS snapshots.
    Process.delete(@ecto_key)

    if :ets.whereis(:excessibility_snapshots) != :undefined do
      :ets.delete_all_objects(:excessibility_snapshots)
    end

    TelemetryCapture.attach()

    on_exit(fn ->
      TelemetryCapture.detach()

      if :ets.whereis(:excessibility_snapshots) != :undefined do
        :ets.delete_all_objects(:excessibility_snapshots)
      end

      Process.delete(@ecto_key)
      File.rm_rf!("test/excessibility")
    end)

    :ok
  end

  # --- drivers ---------------------------------------------------------------

  # Buffer one Ecto query into the process dictionary, identified by `source`
  # (and a distinct SQL string) so membership can be asserted precisely.
  defp fire_query(source) do
    TelemetryCapture.handle_ecto_query(
      [:my_app, :repo, :query],
      %{total_time: System.convert_time_unit(1, :millisecond, :native)},
      %{
        source: source,
        query: "SELECT * FROM #{source} WHERE id = $1",
        repo: nil
      },
      nil
    )
  end

  defp socket(assigns \\ %{count: 1}) do
    %{assigns: assigns, view: TestLive}
  end

  defp emit(event, metadata) do
    TelemetryCapture.handle_event(event, %{duration: 10}, metadata, nil)
  end

  defp mount_start, do: emit([:phoenix, :live_view, :mount, :start], %{})
  defp mount_stop, do: emit([:phoenix, :live_view, :mount, :stop], %{socket: socket()})

  defp handle_event_stop(name),
    do: emit([:phoenix, :live_view, :handle_event, :stop], %{socket: socket(), params: %{"event" => name}})

  defp handle_params_stop, do: emit([:phoenix, :live_view, :handle_params, :stop], %{socket: socket()})

  defp render_stop, do: emit([:phoenix, :live_view, :render, :stop], %{socket: socket()})

  # --- assertions ------------------------------------------------------------

  defp snapshot_for(event_type) do
    Enum.find(TelemetryCapture.get_snapshots(), &(&1.event_type == event_type))
  end

  defp query_sources(snapshot), do: Enum.map(snapshot.ecto_queries, & &1.source)

  # The query identified by `source` appears on exactly `expected_event_type`'s
  # snapshot and on no other captured snapshot.
  defp assert_query_only_on(source, expected_event_type) do
    snapshots = TelemetryCapture.get_snapshots()
    expected = Enum.find(snapshots, &(&1.event_type == expected_event_type))

    assert expected, "expected a snapshot for #{inspect(expected_event_type)}"

    assert source in query_sources(expected),
           "expected query #{inspect(source)} on #{expected_event_type}, got #{inspect(query_sources(expected))}"

    for snap <- snapshots, snap.event_type != expected_event_type do
      refute source in query_sources(snap),
             "query #{inspect(source)} leaked onto #{snap.event_type}"
    end
  end

  # --- scenario 1: pre-mount setup seeds do NOT attach to mount (#151) --------

  test "pre-mount setup seed queries do not attach to mount" do
    # Simulate `setup` seeds running in the (static-mount) process BEFORE the
    # LiveView mounts.
    fire_query("seed_users")
    fire_query("seed_orgs")

    # mount.start must flush/discard the buffered seeds...
    mount_start()
    # ...so mount.stop captures none of them.
    mount_stop()

    mount = snapshot_for("mount")
    assert mount
    assert mount.ecto_queries == []
    refute "seed_users" in query_sources(mount)
    refute "seed_orgs" in query_sources(mount)

    # And the seeds appear on no captured snapshot at all.
    for snap <- TelemetryCapture.get_snapshots() do
      refute "seed_users" in query_sources(snap)
      refute "seed_orgs" in query_sources(snap)
    end
  end

  # --- scenario 2: handle_event query attributes to the event, not render -----

  test "a query fired in handle_event attributes to that event, not the following render" do
    fire_query("event_products")
    # The query was buffered during the event handler; handle_event.stop captures it.
    handle_event_stop("save")
    # A subsequent render with no new query must capture none.
    render_stop()

    assert_query_only_on("event_products", "handle_event:save")

    render = snapshot_for("render")
    assert render
    assert render.ecto_queries == []
  end

  # --- scenario 3: adjacent handle_events don't bleed queries across ----------

  test "adjacent handle_events do not bleed queries across" do
    fire_query("query_a")
    handle_event_stop("a")

    fire_query("query_b")
    handle_event_stop("b")

    a = snapshot_for("handle_event:a")
    b = snapshot_for("handle_event:b")

    assert query_sources(a) == ["query_a"]
    assert query_sources(b) == ["query_b"]

    assert_query_only_on("query_a", "handle_event:a")
    assert_query_only_on("query_b", "handle_event:b")
  end

  # --- scenario 4: buffered-flush boundary across message-driven ordering ------

  # The real `handle_info` capture path (`on_mount/4` -> `handle_info_hook/2` ->
  # `record_handle_info/2`) is opt-in and gated on a CONNECTED LiveView socket
  # plus `EXCESSIBILITY_TELEMETRY_CAPTURE=true`, and its recording functions are
  # private. Driving it truly end-to-end requires a real connected LiveView (as
  # `handle_info_capture_test.exs` notes, that is exercised against the demo
  # app). Rather than fabricate a half-real hook, we lock the SAME buffered-flush
  # boundary that `record_handle_info/2` depends on: it calls the identical
  # `flush_ecto_queries/0` before `store_snapshot/7`, so a query buffered before
  # one `:stop` must attach to THAT callback and not the next. We assert that
  # boundary across a mount -> handle_params -> handle_event ordering (the
  # closest cleanly-unit-drivable equivalent), which regression-locks the flush
  # boundary the handle_info span relies on.
  test "buffered queries flush to the correct callback across ordered lifecycle events" do
    mount_start()
    mount_stop()

    # Buffered before handle_params.stop -> attributes to handle_params.
    fire_query("params_query")
    handle_params_stop()

    # Buffered before the next handle_event.stop -> attributes to that event.
    fire_query("click_query")
    handle_event_stop("click")

    mount = snapshot_for("mount")
    assert mount.ecto_queries == []

    assert_query_only_on("params_query", "handle_params")
    assert_query_only_on("click_query", "handle_event:click")
  end
end
