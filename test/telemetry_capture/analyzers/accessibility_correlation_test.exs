defmodule Excessibility.TelemetryCapture.Analyzers.AccessibilityCorrelationTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.AccessibilityCorrelation

  describe "name/0" do
    test "returns :accessibility_correlation" do
      assert AccessibilityCorrelation.name() == :accessibility_correlation
    end
  end

  describe "default_enabled?/0" do
    test "returns false" do
      assert AccessibilityCorrelation.default_enabled?() == false
    end
  end

  describe "analyze/2" do
    test "identifies events with high a11y risk - modal" do
      timeline = %{
        timeline: [
          %{event: "mount", sequence: 1, changes: nil},
          %{
            event: "handle_event:open_modal",
            sequence: 2,
            changes: %{modal_open: {false, true}}
          },
          %{
            event: "handle_event:update_list",
            sequence: 3,
            changes: %{items: {[], ["a", "b"]}}
          }
        ]
      }

      result = AccessibilityCorrelation.analyze(timeline, [])

      # Modal opening is a11y-sensitive
      assert Enum.any?(result.findings, &String.contains?(&1.message, "modal"))
    end

    test "flags dynamic content changes" do
      timeline = %{
        timeline: [
          %{
            event: "handle_event:load_more",
            sequence: 1,
            changes: %{items: {[1, 2], [1, 2, 3, 4, 5]}}
          }
        ]
      }

      result = AccessibilityCorrelation.analyze(timeline, [])

      assert Enum.any?(result.findings, fn f ->
               String.contains?(f.message, "items") or String.contains?(f.message, "list")
             end)
    end

    test "no findings for simple state changes" do
      timeline = %{
        timeline: [
          %{
            event: "handle_event:increment",
            sequence: 1,
            changes: %{count: {1, 2}}
          }
        ]
      }

      result = AccessibilityCorrelation.analyze(timeline, [])

      # Simple counter is not a11y-sensitive
      assert Enum.empty?(result.findings)
    end

    test "includes a11y recommendations" do
      timeline = %{
        timeline: [
          %{
            event: "handle_event:show_error",
            sequence: 1,
            changes: %{error_message: {nil, "Invalid input"}}
          }
        ]
      }

      result = AccessibilityCorrelation.analyze(timeline, [])

      finding = List.first(result.findings)
      assert Map.has_key?(finding.metadata, :recommendations)
    end

    test "detects loading state changes" do
      timeline = %{
        timeline: [
          %{
            event: "handle_event:fetch",
            sequence: 1,
            changes: %{loading: {false, true}}
          }
        ]
      }

      result = AccessibilityCorrelation.analyze(timeline, [])

      assert Enum.any?(result.findings, &String.contains?(&1.message, "loading"))
    end

    test "detects dialog/popup patterns" do
      timeline = %{
        timeline: [
          %{
            event: "handle_event:open",
            sequence: 1,
            changes: %{show_dialog: {false, true}}
          }
        ]
      }

      result = AccessibilityCorrelation.analyze(timeline, [])

      assert length(result.findings) > 0
    end

    test "handles empty timeline" do
      result = AccessibilityCorrelation.analyze(%{timeline: []}, [])

      assert result.findings == []
    end

    test "handles nil changes" do
      timeline = %{
        timeline: [
          %{event: "mount", sequence: 1, changes: nil}
        ]
      }

      result = AccessibilityCorrelation.analyze(timeline, [])

      assert result.findings == []
    end
  end
end
