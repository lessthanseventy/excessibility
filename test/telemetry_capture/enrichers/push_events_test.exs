defmodule Excessibility.TelemetryCapture.Enrichers.PushEventsTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.PushEvents

  describe "name/0" do
    test "returns :push_events" do
      assert PushEvents.name() == :push_events
    end
  end

  describe "cost/0" do
    test "returns :moderate" do
      assert PushEvents.cost() == :moderate
    end
  end

  describe "enrich/2" do
    test "returns empty when no push_events in opts" do
      result = PushEvents.enrich(%{}, [])

      assert result.push_events == []
      assert result.push_event_count == 0
    end

    test "returns push events from opts" do
      events = [
        %{event_name: "update-chart", payload_size: 450},
        %{event_name: "update-chart", payload_size: 200}
      ]

      result = PushEvents.enrich(%{}, push_events: events)

      assert length(result.push_events) == 2
      assert result.push_event_count == 2
    end
  end

  describe "store operations" do
    setup do
      PushEvents.start_store()
      on_exit(fn -> PushEvents.stop_store() end)
    end

    test "records and retrieves push events" do
      PushEvents.record_push_event(%{event_name: "update-chart", payload_size: 100})
      events = PushEvents.get_push_events()

      assert length(events) == 1
      assert List.first(events).event_name == "update-chart"
    end

    test "clear removes all events" do
      PushEvents.record_push_event(%{event_name: "test", payload_size: 10})
      PushEvents.clear()

      assert PushEvents.get_push_events() == []
    end
  end
end
