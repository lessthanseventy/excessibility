defmodule Excessibility.TelemetryCapture.Analyzers.PushEventVolumeTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.PushEventVolume

  describe "name/0" do
    test "returns :push_event_volume" do
      assert PushEventVolume.name() == :push_event_volume
    end
  end

  describe "default_enabled?/0" do
    test "returns false" do
      assert PushEventVolume.default_enabled?() == false
    end
  end

  describe "requires_enrichers/0" do
    test "declares push_events enricher dependency" do
      assert PushEventVolume.requires_enrichers() == [:push_events]
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      result = PushEventVolume.analyze(%{timeline: []}, [])
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects excessive push_events from single handler" do
      push_events = for _ <- 1..8, do: %{event_name: "update-chart", payload_size: 100}

      timeline = %{
        timeline: [
          %{sequence: 1, event: "handle_info:update", push_events: push_events, push_event_count: 8}
        ]
      }

      result = PushEventVolume.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.message =~ "update-chart"
      assert finding.message =~ "8"
    end

    test "no findings for few push_events" do
      timeline = %{
        timeline: [
          %{
            sequence: 1,
            event: "handle_info:update",
            push_events: [%{event_name: "chart", payload_size: 100}],
            push_event_count: 1
          }
        ]
      }

      result = PushEventVolume.analyze(timeline, [])
      assert result.findings == []
    end

    test "suggests batching for repeated same-name push_events" do
      push_events = for _ <- 1..10, do: %{event_name: "update-chart", payload_size: 50}

      timeline = %{
        timeline: [
          %{sequence: 1, event: "handle_info:update", push_events: push_events, push_event_count: 10}
        ]
      }

      result = PushEventVolume.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &(&1.message =~ "batch"))
    end

    test "handles empty timeline" do
      result = PushEventVolume.analyze(%{timeline: []}, [])
      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles timeline without push_event data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "render"}
        ]
      }

      result = PushEventVolume.analyze(timeline, [])
      assert result.findings == []
    end
  end
end
