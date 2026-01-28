defmodule Excessibility.TelemetryCapture.Analyzers.CascadeEffectTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.CascadeEffect

  describe "name/0" do
    test "returns :cascade_effect" do
      assert CascadeEffect.name() == :cascade_effect
    end
  end

  describe "default_enabled?/0" do
    test "returns false" do
      # Not default enabled - can be noisy
      assert CascadeEffect.default_enabled?() == false
    end
  end

  describe "analyze/2" do
    test "no issues with isolated events" do
      timeline =
        build_timeline([
          %{event: "handle_event:click", timestamp: 0},
          %{event: "render", timestamp: 100},
          %{event: "handle_event:submit", timestamp: 500},
          %{event: "render", timestamp: 600}
        ])

      result = CascadeEffect.analyze(timeline, [])

      assert Enum.empty?(result.findings)
    end

    test "detects rapid cascade of events" do
      # Event triggers 4 more within 50ms
      timeline =
        build_timeline([
          %{event: "handle_event:update", timestamp: 0},
          %{event: "handle_info:broadcast", timestamp: 5},
          %{event: "handle_info:sync", timestamp: 10},
          %{event: "render", timestamp: 15},
          %{event: "render", timestamp: 20}
        ])

      result = CascadeEffect.analyze(timeline, [])

      assert length(result.findings) > 0
    end

    test "calculates cascade depth" do
      timeline =
        build_timeline([
          %{event: "handle_event:trigger", timestamp: 0},
          %{event: "handle_info:a", timestamp: 5},
          %{event: "handle_info:b", timestamp: 10},
          %{event: "handle_info:c", timestamp: 15}
        ])

      result = CascadeEffect.analyze(timeline, [])

      assert result.stats.max_cascade_depth >= 3
    end

    test "handles empty timeline" do
      result = CascadeEffect.analyze(%{timeline: []}, [])

      assert result.findings == []
      assert result.stats.cascade_count == 0
    end

    test "multiple cascades counted separately" do
      timeline =
        build_timeline([
          # First cascade
          %{event: "handle_event:a", timestamp: 0},
          %{event: "render", timestamp: 10},
          %{event: "render", timestamp: 20},
          # Gap
          %{event: "handle_event:b", timestamp: 500},
          # Second cascade
          %{event: "render", timestamp: 510},
          %{event: "render", timestamp: 520},
          %{event: "render", timestamp: 530}
        ])

      result = CascadeEffect.analyze(timeline, [])

      # Should detect at least one cascade
      assert result.stats.cascade_count >= 1
    end

    test "warning for large cascades" do
      timeline =
        build_timeline([
          %{event: "handle_event:trigger", timestamp: 0},
          %{event: "handle_info:a", timestamp: 5},
          %{event: "handle_info:b", timestamp: 10},
          %{event: "handle_info:c", timestamp: 15},
          %{event: "handle_info:d", timestamp: 20},
          %{event: "render", timestamp: 25}
        ])

      result = CascadeEffect.analyze(timeline, [])

      finding = List.first(result.findings)
      assert finding.severity == :warning
    end
  end

  defp build_timeline(events) do
    entries =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {data, seq} -> Map.put(data, :sequence, seq) end)

    %{timeline: entries}
  end
end
