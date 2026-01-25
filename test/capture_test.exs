defmodule Excessibility.CaptureTest do
  use ExUnit.Case
  use Excessibility

  import Mox

  setup :verify_on_exit!

  describe "auto-capture" do
    @tag capture_snapshots: true
    test "initializes capture state", context do
      state = Excessibility.Capture.get_state()

      assert state != nil
      assert state.test_name == context[:test]
      assert state.sequence == 0
      assert state.events == []
    end

    @tag capture_snapshots: true
    test "records events", _context do
      metadata = Excessibility.Capture.record_event("click", %{foo: "bar"})

      assert metadata.sequence == 1
      assert metadata.event_type == "click"
      assert metadata.assigns == %{foo: "bar"}
    end

    @tag capture_snapshots: true
    test "builds timeline", _context do
      Excessibility.Capture.record_event("initial_render", %{})
      Excessibility.Capture.record_event("click", %{clicked: true})
      Excessibility.Capture.record_event("change", %{value: "test"})

      timeline = Excessibility.Capture.get_timeline()

      assert timeline.total_events == 3
      assert length(timeline.events) == 3
      assert Enum.at(timeline.events, 0).type == "initial_render"
      assert Enum.at(timeline.events, 1).type == "click"
      assert Enum.at(timeline.events, 2).type == "change"
    end
  end

  describe "metadata in snapshots" do
    @tag capture_snapshots: true
    test "adds metadata to snapshot", _context do
      # Create a simple conn
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<html><body>Test</body></html>")

      # Record an event first to get metadata
      Excessibility.Capture.record_event("test_event", %{test: "value"})

      # Capture snapshot
      html_snapshot(conn, event_type: "test_event", name: "capture_test.html")

      # Read the snapshot and check metadata
      snapshot_path = Path.join([File.cwd!(), "test/excessibility/html_snapshots", "capture_test.html"])
      assert File.exists?(snapshot_path)

      content = File.read!(snapshot_path)
      assert content =~ "Excessibility Snapshot"
      assert content =~ "Event: test_event"
      assert content =~ "Sequence: 1"

      # Cleanup
      File.rm!(snapshot_path)
    end
  end
end
