defmodule Integration.TelemetryAnalysisTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Formatter
  alias Excessibility.TelemetryCapture.Registry
  alias Excessibility.TelemetryCapture.Timeline

  describe "end-to-end telemetry analysis flow" do
    test "enrichers add data to timeline events" do
      snapshots = [
        build_snapshot("mount", %{user: "alice"}),
        build_snapshot("handle_event:click", %{user: "alice", data: String.duplicate("x", 1000)})
      ]

      timeline = Timeline.build_timeline(snapshots, "test", [])

      # Verify enrichments are present
      assert Enum.all?(timeline.timeline, &Map.has_key?(&1, :memory_size))

      # Second event should have larger memory
      [event1, event2] = timeline.timeline
      assert event2.memory_size > event1.memory_size
    end

    test "analyzers detect issues in timeline" do
      # Create timeline with deliberate memory bloat
      snapshots =
        Enum.map(1..5, fn i ->
          size = if i == 3, do: 10_000, else: 100
          assigns = %{data: String.duplicate("x", size)}
          build_snapshot("event_#{i}", assigns)
        end)

      timeline = Timeline.build_timeline(snapshots, "test", [])

      # Run memory analyzer
      memory_analyzer = Registry.get_analyzer(:memory)
      result = memory_analyzer.analyze(timeline, [])

      # Should detect the bloat at event 3
      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &String.contains?(&1.message, "grew"))
    end

    test "formatter produces markdown from analysis results" do
      results = %{
        memory: %{
          findings: [
            %{
              severity: :warning,
              message: "Memory grew 10x",
              events: [1, 2],
              metadata: %{}
            }
          ],
          stats: %{min: 100, max: 1000, avg: 550}
        }
      }

      markdown = Formatter.format_analysis_results(results, [])

      assert markdown =~ "## Memory Analysis"
      assert markdown =~ "⚠️"
      assert markdown =~ "Memory grew 10x"
      assert markdown =~ "100 B"
      assert markdown =~ "1000 B"
    end

    test "complete flow: snapshots -> timeline -> analysis -> markdown" do
      # Build snapshots with memory leak pattern
      snapshots =
        [100, 200, 400, 800, 1600]
        |> Enum.with_index(1)
        |> Enum.map(fn {size, i} ->
          build_snapshot("event_#{i}", %{data: String.duplicate("x", size)})
        end)

      # Build timeline (enrichers run automatically)
      timeline = Timeline.build_timeline(snapshots, "leak_test", [])

      # Run analyzers
      analyzers = Registry.get_default_analyzers()

      analysis_results =
        Map.new(analyzers, fn analyzer -> {analyzer.name(), analyzer.analyze(timeline, [])} end)

      # Format results
      markdown = Formatter.format_analysis_results(analysis_results, [])

      # Verify leak detected
      assert markdown =~ "Memory Analysis"
      assert markdown =~ "leak"
      assert markdown =~ "🔴"
    end
  end

  defp build_snapshot(event_type, assigns) do
    %{
      event_type: event_type,
      assigns: assigns,
      timestamp: DateTime.utc_now(),
      view_module: TestModule
    }
  end
end
