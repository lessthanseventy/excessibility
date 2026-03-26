defmodule Excessibility.TelemetryCapture.Analyzers.MessageFloodingTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.MessageFlooding

  describe "name/0" do
    test "returns :message_flooding" do
      assert MessageFlooding.name() == :message_flooding
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert MessageFlooding.default_enabled?() == true
    end
  end

  describe "requires_enrichers/0" do
    test "requires no enrichers" do
      assert MessageFlooding.requires_enrichers() == []
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      result = MessageFlooding.analyze(%{timeline: []}, [])
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects high-frequency handle_info events" do
      base = ~U[2026-03-25 12:00:00.000Z]

      events =
        for i <- 1..15 do
          %{
            sequence: i,
            event: "handle_info:tick",
            timestamp: DateTime.add(base, i * 13, :millisecond),
            duration_since_previous_ms: 13
          }
        end

      result = MessageFlooding.analyze(%{timeline: events}, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.message =~ "handle_info"
      assert finding.message =~ "tick"
    end

    test "detects excessive total count of handle_info events" do
      events =
        for i <- 1..25 do
          %{
            sequence: i,
            event: "handle_info:refresh",
            timestamp: DateTime.add(~U[2026-03-25 12:00:00Z], i * 100, :millisecond),
            duration_since_previous_ms: 100
          }
        end

      result = MessageFlooding.analyze(%{timeline: events}, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &(&1.message =~ "25"))
    end

    test "ignores non-handle_info events" do
      events =
        for i <- 1..25 do
          %{
            sequence: i,
            event: "handle_event:click",
            timestamp: DateTime.add(~U[2026-03-25 12:00:00Z], i * 10, :millisecond),
            duration_since_previous_ms: 10
          }
        end

      result = MessageFlooding.analyze(%{timeline: events}, [])
      assert result.findings == []
    end

    test "no findings for low-frequency handle_info" do
      events = [
        %{
          sequence: 1,
          event: "handle_info:update",
          timestamp: ~U[2026-03-25 12:00:00Z],
          duration_since_previous_ms: nil
        },
        %{
          sequence: 2,
          event: "handle_info:update",
          timestamp: ~U[2026-03-25 12:00:01Z],
          duration_since_previous_ms: 1000
        },
        %{
          sequence: 3,
          event: "handle_info:update",
          timestamp: ~U[2026-03-25 12:00:02Z],
          duration_since_previous_ms: 1000
        }
      ]

      result = MessageFlooding.analyze(%{timeline: events}, [])
      assert result.findings == []
    end

    test "handles empty timeline" do
      result = MessageFlooding.analyze(%{timeline: []}, [])
      assert result.findings == []
      assert result.stats == %{}
    end

    test "calculates flooding statistics" do
      events =
        for i <- 1..12 do
          %{
            sequence: i,
            event: "handle_info:tick",
            timestamp: DateTime.add(~U[2026-03-25 12:00:00Z], i * 15, :millisecond),
            duration_since_previous_ms: 15
          }
        end

      result = MessageFlooding.analyze(%{timeline: events}, [])

      assert Map.has_key?(result.stats, :handle_info_counts)
    end
  end
end
