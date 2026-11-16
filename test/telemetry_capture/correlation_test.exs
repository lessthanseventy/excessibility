defmodule Excessibility.TelemetryCapture.CorrelationTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.SnapshotStore
  alias Excessibility.TelemetryCapture.Timeline
  alias Phoenix.LiveView.Socket

  @output "test/excessibility"

  setup do
    previous = System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE")
    System.put_env("EXCESSIBILITY_TELEMETRY_CAPTURE", "true")
    SnapshotStore.ensure_started()
    TelemetryCapture.clear_snapshots()
    File.rm_rf!(@output)

    on_exit(fn ->
      if previous,
        do: System.put_env("EXCESSIBILITY_TELEMETRY_CAPTURE", previous),
        else: System.delete_env("EXCESSIBILITY_TELEMETRY_CAPTURE")

      TelemetryCapture.clear_snapshots()
      File.rm_rf!(@output)
    end)
  end

  defp socket(transport_pid \\ nil),
    do: %Socket{view: MyApp.Live, transport_pid: transport_pid, assigns: %{__changed__: %{}, n: 1}}

  defp fire_query(source) do
    TelemetryCapture.handle_ecto_query(
      [:my_app, :repo, :query],
      %{total_time: 1},
      %{source: source, query: "SELECT * FROM #{source}", repo: nil},
      nil
    )
  end

  defp mount(socket) do
    TelemetryCapture.handle_event([:phoenix, :live_view, :mount, :stop], %{duration: 1}, %{socket: socket}, nil)
  end

  test "html_snapshot marks the timeline with the snapshot's file name" do
    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<html><body>Hi</body></html>")

    Excessibility.Snapshot.html_snapshot(conn, %{line: 1}, __MODULE__, name: "step_01_landing.html")

    assert [%{event_type: "snapshot", snapshot: "step_01_landing.html"}] = TelemetryCapture.get_snapshots()
  end

  test "no snapshot mark is recorded when capture is off" do
    System.delete_env("EXCESSIBILITY_TELEMETRY_CAPTURE")

    TelemetryCapture.record_html_snapshot("step.html")

    assert TelemetryCapture.get_snapshots() == []
  end

  test "each event records whether the socket was connected" do
    mount(socket())
    mount(socket(self()))

    assert [%{connected?: false}, %{connected?: true}] = TelemetryCapture.get_snapshots()
  end

  test "events fired inside without_capture/1 are dropped" do
    assert TelemetryCapture.without_capture(fn -> mount(socket()) && :rendered end) == :rendered
    mount(socket(self()))

    assert [%{connected?: true}] = TelemetryCapture.get_snapshots()
  end

  test "without_capture/1 keeps queries buffered before it and drops the ones fired inside" do
    fire_query("before")

    TelemetryCapture.without_capture(fn ->
      TelemetryCapture.without_capture(fn -> :ok end)
      fire_query("head_render")
      mount(socket())
    end)

    mount(socket(self()))

    assert [%{connected?: true, ecto_queries: [%{source: "before"}]}] = TelemetryCapture.get_snapshots()
  end

  test "a LiveView handle_event without an event name is still captured" do
    TelemetryCapture.handle_event([:phoenix, :live_view, :handle_event, :stop], %{}, %{socket: socket()}, nil)

    assert [%{event_type: "handle_event:event"}] = TelemetryCapture.get_snapshots()
  end

  test "two instances of one LiveComponent are diffed separately" do
    snapshots =
      for {id, n, s} <- [{"a", 1, 0}, {"b", 5, 1}, {"a", 2, 2}] do
        %{
          event_type: "handle_event:inc",
          assigns: %{n: n},
          timestamp: DateTime.add(~U[2026-01-25 10:00:00Z], s),
          view_module: MyApp.Live,
          component: MyApp.Counter,
          component_id: id
        }
      end

    assert [%{changes: nil}, %{changes: nil}, %{changes: %{"n" => {1, 2}}}] =
             Timeline.build_timeline(snapshots, "t").timeline
  end

  test "without_snapshot_marks/1 handles string keys, a nil timeline and events without a name" do
    assert %{"timeline" => [%{"event" => "mount"}]} =
             Timeline.without_snapshot_marks(%{"timeline" => [%{"event" => "mount"}, %{"event" => "snapshot"}]})

    assert Timeline.without_snapshot_marks(%{timeline: nil}) == %{timeline: nil}
    assert Timeline.without_snapshot_marks(%{timeline: [%{sequence: 1}]}) == %{timeline: [%{sequence: 1}]}
  end

  test "a test writes and clears only the events of LiveViews it started" do
    other_test = spawn(fn -> Process.sleep(:infinity) end)

    fn ->
      Process.put(:"$callers", [other_test])
      mount(socket(self()))
    end
    |> Task.async()
    |> Task.await()

    mount(socket())
    TelemetryCapture.write_snapshots(MyApp.PageTest, :"test mine", self())
    TelemetryCapture.clear_snapshots(self())

    assert %{"timeline" => [%{"connected?" => false}]} =
             @output |> Path.join("timeline.json") |> File.read!() |> Jason.decode!()

    assert [%{connected?: true}] = TelemetryCapture.get_snapshots()
  end

  test "tests whose names differ only in punctuation get separate timeline files" do
    mount(socket(self()))
    TelemetryCapture.write_snapshots(MyApp.PageTest, :"test x?", self())
    TelemetryCapture.write_snapshots(MyApp.PageTest, :"test x!", self())

    assert [_, _] = File.ls!(Path.join(@output, "timelines/MyApp.PageTest"))
  end

  test "a snapshot mark carries no state and does not move the diff base" do
    snapshots = [
      %{event_type: "mount", assigns: %{n: 1}, timestamp: ~U[2026-01-25 10:00:00Z], view_module: MyApp.Live},
      %{
        event_type: "snapshot",
        snapshot: "step.html",
        assigns: %{},
        timestamp: ~U[2026-01-25 10:00:01Z],
        view_module: nil
      },
      %{event_type: "handle_event:inc", assigns: %{n: 2}, timestamp: ~U[2026-01-25 10:00:03Z], view_module: MyApp.Live}
    ]

    timeline = Timeline.build_timeline(snapshots, "t")
    [_mount, mark, inc] = timeline.timeline

    assert %{event: "snapshot", snapshot: "step.html", sequence: 2, duration_since_previous_ms: 1000} = mark
    refute Map.has_key?(mark, :changes)
    assert inc.changes == %{"n" => {1, 2}}
    assert inc.duration_since_previous_ms == 3000

    markdown = Excessibility.TelemetryCapture.Formatter.format_markdown(timeline, [])
    assert markdown =~ "| 2 | +1000ms | snapshot | step.html |"

    assert ["mount", "handle_event:inc"] ==
             timeline |> Timeline.without_snapshot_marks() |> Map.fetch!(:timeline) |> Enum.map(& &1.event)
  end

  test "each test's timeline is also written under timelines/<module>/<test>.json" do
    mount(socket(self()))
    TelemetryCapture.write_snapshots(MyApp.PageTest, :"test user signs in", self())

    assert [per_test] = Path.wildcard(Path.join(@output, "timelines/MyApp.PageTest/test_user_signs_in-*.json"))
    assert File.read!(per_test) == File.read!(Path.join(@output, "timeline.json"))
  end
end
