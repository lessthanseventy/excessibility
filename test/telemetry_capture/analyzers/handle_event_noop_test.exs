defmodule Excessibility.TelemetryCapture.Analyzers.HandleEventNoopTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.HandleEventNoop

  describe "name/0" do
    test "returns :handle_event_noop" do
      assert HandleEventNoop.name() == :handle_event_noop
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert HandleEventNoop.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "no issues when events modify state" do
      timeline =
        build_timeline([
          %{event: "handle_event:click", changes: %{count: {1, 2}}},
          %{event: "handle_event:submit", changes: %{status: {:pending, :done}}}
        ])

      result = HandleEventNoop.analyze(timeline, [])

      assert Enum.empty?(result.findings)
    end

    test "detects noop handle_event" do
      timeline =
        build_timeline([
          %{event: "handle_event:click", changes: %{}},
          %{event: "handle_event:click", changes: %{}}
        ])

      result = HandleEventNoop.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &String.contains?(&1.message, "click"))
    end

    test "ignores mount and render events" do
      timeline =
        build_timeline([
          %{event: "mount", changes: nil},
          %{event: "render", changes: %{}}
        ])

      result = HandleEventNoop.analyze(timeline, [])

      assert Enum.empty?(result.findings)
      assert result.stats.noop_count == 0
    end

    test "suggests throttle for input events" do
      timeline =
        build_timeline([
          %{event: "handle_event:validate", changes: %{}},
          %{event: "handle_event:validate", changes: %{}},
          %{event: "handle_event:validate", changes: %{}}
        ])

      result = HandleEventNoop.analyze(timeline, [])

      finding = List.first(result.findings)

      assert String.contains?(finding.message, "throttle") or
               String.contains?(finding.message, "debounce")
    end

    test "groups by event name in stats" do
      timeline =
        build_timeline([
          %{event: "handle_event:click", changes: %{}},
          %{event: "handle_event:click", changes: %{}},
          %{event: "handle_event:hover", changes: %{}}
        ])

      result = HandleEventNoop.analyze(timeline, [])

      assert result.stats.noop_by_event["click"] == 2
      assert result.stats.noop_by_event["hover"] == 1
    end

    test "handles empty timeline" do
      result = HandleEventNoop.analyze(%{timeline: []}, [])

      assert result.findings == []
      assert result.stats.noop_count == 0
    end

    test "warning severity for 3+ noops of same event" do
      timeline =
        build_timeline([
          %{event: "handle_event:check", changes: %{}},
          %{event: "handle_event:check", changes: %{}},
          %{event: "handle_event:check", changes: %{}}
        ])

      result = HandleEventNoop.analyze(timeline, [])

      finding = List.first(result.findings)
      assert finding.severity == :warning
    end

    test "info severity for less than 3 noops" do
      timeline =
        build_timeline([
          %{event: "handle_event:check", changes: %{}},
          %{event: "handle_event:check", changes: %{}}
        ])

      result = HandleEventNoop.analyze(timeline, [])

      finding = List.first(result.findings)
      assert finding.severity == :info
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
