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
      %{event_type: "handle_event:inc", assigns: %{n: 2}, timestamp: ~U[2026-01-25 10:00:02Z], view_module: MyApp.Live}
    ]

    timeline = Timeline.build_timeline(snapshots, "t")
    [_mount, mark, inc] = timeline.timeline

    assert %{event: "snapshot", snapshot: "step.html", sequence: 2, duration_since_previous_ms: 1000} = mark
    refute Map.has_key?(mark, :changes)
    assert inc.changes == %{"n" => {1, 2}}

    assert ["mount", "handle_event:inc"] ==
             timeline |> Timeline.without_snapshot_marks() |> Map.fetch!(:timeline) |> Enum.map(& &1.event)
  end

  test "each test's timeline is also written under timelines/<module>/<test>.json" do
    mount(socket(self()))
    TelemetryCapture.write_snapshots(MyApp.PageTest, :"test user signs in")

    per_test = Path.join(@output, "timelines/MyApp.PageTest/test_user_signs_in.json")
    assert File.read!(per_test) == File.read!(Path.join(@output, "timeline.json"))
  end
end
