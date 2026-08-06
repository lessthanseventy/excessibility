defmodule Excessibility.TelemetryCapture.EctoCaptureTest do
  @moduledoc """
  Issue #147: the Ecto capture layer must actually record queries so
  `ecto_query_analysis` can fire. These exercise the real telemetry path —
  the same `[..., :query]` event Ecto emits — end to end, without a database.
  """
  # Not async: mutates application env and attaches global telemetry handlers.
  use ExUnit.Case

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.Timeline

  defmodule DerivedRepo do
    @moduledoc false
    # No config/0 — the query event is derived from the module name.
  end

  defmodule PrefixedRepo do
    @moduledoc false
    def config, do: [telemetry_prefix: [:my_app, :repo]]
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:excessibility, :ecto_repos)
      TelemetryCapture.detach()
      TelemetryCapture.flush_ecto_queries()
    end)

    :ok
  end

  defp emit_query(event, source, query) do
    :telemetry.execute(
      event,
      %{total_time: System.convert_time_unit(2, :millisecond, :native)},
      %{source: source, query: query, repo: nil}
    )
  end

  test "derives a repo's query event from its module name" do
    Application.put_env(:excessibility, :ecto_repos, [DerivedRepo])

    assert TelemetryCapture.ecto_query_events() == [
             [:excessibility, :telemetry_capture, :ecto_capture_test, :derived_repo, :query]
           ]
  end

  test "honors a repo's custom :telemetry_prefix" do
    Application.put_env(:excessibility, :ecto_repos, [PrefixedRepo])

    assert TelemetryCapture.ecto_query_events() == [[:my_app, :repo, :query]]
  end

  test "captures queries emitted at the configured repo's event, oldest first, then flushes" do
    Application.put_env(:excessibility, :ecto_repos, [PrefixedRepo])
    TelemetryCapture.attach()
    on_exit(&TelemetryCapture.detach/0)

    emit_query([:my_app, :repo, :query], "products", "SELECT * FROM products")
    emit_query([:my_app, :repo, :query], "products", "SELECT * FROM products WHERE id = 1")

    queries = TelemetryCapture.flush_ecto_queries()

    assert length(queries) == 2
    assert Enum.map(queries, & &1.source) == ["products", "products"]
    assert hd(queries).operation == :select
    assert hd(queries).duration_ms == 2.0

    # A flush clears the buffer so queries attribute to a single event.
    assert TelemetryCapture.flush_ecto_queries() == []
  end

  test "no handler is attached (and nothing captured) when no repos are configured" do
    TelemetryCapture.attach()
    on_exit(&TelemetryCapture.detach/0)

    assert TelemetryCapture.ecto_query_events() == []
    # An unrelated Ecto event fires but nothing listens for it.
    emit_query([:some_other, :repo, :query], "x", "SELECT 1")
    assert TelemetryCapture.flush_ecto_queries() == []
  end

  test "the timeline attributes captured queries to their event (enricher wiring)" do
    n_plus_one =
      for _ <- 1..15,
          do: %{source: "products", operation: :select, duration_ms: 1.0, query: "SELECT", repo: nil}

    snapshots = [
      %{
        event_type: "mount",
        assigns: %{},
        timestamp: DateTime.utc_now(),
        view_module: SomeView,
        ecto_queries: []
      },
      %{
        event_type: "handle_event:load",
        assigns: %{},
        timestamp: DateTime.utc_now(),
        view_module: SomeView,
        ecto_queries: n_plus_one
      }
    ]

    timeline = Timeline.build_timeline(snapshots, "t", [])
    [mount_event, load_event] = timeline.timeline

    assert mount_event.ecto_query_count == 0
    assert load_event.ecto_query_count == 15
    assert load_event.ecto_total_query_ms == 15.0
  end
end
