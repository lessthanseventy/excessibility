defmodule Excessibility.TelemetryCapture.Analyzers.AssignLifecycleTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.AssignLifecycle

  describe "name/0" do
    test "returns :assign_lifecycle" do
      assert AssignLifecycle.name() == :assign_lifecycle
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert AssignLifecycle.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "no issues when assigns change" do
      timeline =
        build_timeline([
          %{key_state: %{count: 1, user: "Alice"}},
          %{key_state: %{count: 2, user: "Alice"}},
          %{key_state: %{count: 3, user: "Bob"}}
        ])

      result = AssignLifecycle.analyze(timeline, [])

      assert Enum.empty?(result.findings)
    end

    test "detects never-changing assigns" do
      timeline =
        build_timeline([
          %{key_state: %{count: 1, static_config: %{a: 1}}},
          %{key_state: %{count: 2, static_config: %{a: 1}}},
          %{key_state: %{count: 3, static_config: %{a: 1}}},
          %{key_state: %{count: 4, static_config: %{a: 1}}}
        ])

      result = AssignLifecycle.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert :static_config in finding.metadata.stale_assigns
    end

    test "info severity for stale assigns" do
      timeline =
        build_timeline([
          %{key_state: %{status: :ok}},
          %{key_state: %{status: :ok}},
          %{key_state: %{status: :ok}}
        ])

      result = AssignLifecycle.analyze(timeline, [])

      finding = List.first(result.findings)
      assert finding.severity == :info
    end

    test "handles single event timeline" do
      timeline = build_timeline([%{key_state: %{a: 1}}])
      result = AssignLifecycle.analyze(timeline, [])

      # Can't detect staleness with single event
      assert Enum.empty?(result.findings)
    end

    test "handles two event timeline" do
      timeline =
        build_timeline([
          %{key_state: %{a: 1}},
          %{key_state: %{a: 1}}
        ])

      result = AssignLifecycle.analyze(timeline, [])

      # Two events is minimum to detect stale
      assert result.stats.stale_assigns == 1
    end

    test "calculates assign activity stats" do
      timeline =
        build_timeline([
          %{key_state: %{a: 1, b: 1}},
          %{key_state: %{a: 2, b: 1}},
          %{key_state: %{a: 3, b: 1}}
        ])

      result = AssignLifecycle.analyze(timeline, [])

      assert result.stats.total_assigns == 2
      assert result.stats.active_assigns == 1
      assert result.stats.stale_assigns == 1
    end

    test "handles empty timeline" do
      result = AssignLifecycle.analyze(%{timeline: []}, [])

      assert result.findings == []
      assert result.stats.total_assigns == 0
    end

    test "handles missing key_state" do
      timeline =
        build_timeline([
          %{event: "mount"},
          %{event: "render"}
        ])

      result = AssignLifecycle.analyze(timeline, [])

      assert result.findings == []
    end
  end

  defp build_timeline(events) do
    entries =
      events
      |> Enum.with_index(1)
      |> Enum.map(fn {data, seq} ->
        Map.merge(%{sequence: seq, event: "test"}, data)
      end)

    %{timeline: entries}
  end
end
