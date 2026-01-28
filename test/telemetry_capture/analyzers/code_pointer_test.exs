defmodule Excessibility.TelemetryCapture.Analyzers.CodePointerTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.CodePointer

  describe "name/0" do
    test "returns :code_pointer" do
      assert CodePointer.name() == :code_pointer
    end
  end

  describe "default_enabled?/0" do
    test "returns false" do
      assert CodePointer.default_enabled?() == false
    end
  end

  describe "analyze/2" do
    test "maps handle_event to callback" do
      timeline = %{
        timeline: [
          %{event: "handle_event:save_form", view_module: MyApp.FormLive, sequence: 1}
        ]
      }

      result = CodePointer.analyze(timeline, [])

      pointer = List.first(result.stats.pointers)
      assert pointer.event == "handle_event:save_form"
      assert pointer.likely_location =~ "def handle_event(\"save_form\""
      assert pointer.module == MyApp.FormLive
    end

    test "maps mount to mount callback" do
      timeline = %{
        timeline: [
          %{event: "mount", view_module: MyApp.PageLive, sequence: 1}
        ]
      }

      result = CodePointer.analyze(timeline, [])

      pointer = List.first(result.stats.pointers)
      assert pointer.likely_location =~ "def mount"
    end

    test "maps handle_params" do
      timeline = %{
        timeline: [
          %{event: "handle_params", view_module: MyApp.ShowLive, sequence: 1}
        ]
      }

      result = CodePointer.analyze(timeline, [])

      pointer = List.first(result.stats.pointers)
      assert pointer.likely_location =~ "def handle_params"
    end

    test "handles missing view_module" do
      timeline = %{
        timeline: [
          %{event: "handle_event:click", sequence: 1}
        ]
      }

      result = CodePointer.analyze(timeline, [])

      assert length(result.stats.pointers) == 1
      pointer = List.first(result.stats.pointers)
      assert pointer.module == nil
    end

    test "maps render event" do
      timeline = %{
        timeline: [
          %{event: "render", view_module: MyApp.Live, sequence: 1}
        ]
      }

      result = CodePointer.analyze(timeline, [])

      pointer = List.first(result.stats.pointers)
      assert pointer.likely_location =~ "render"
    end

    test "maps handle_info" do
      timeline = %{
        timeline: [
          %{event: "handle_info:tick", view_module: MyApp.TimerLive, sequence: 1}
        ]
      }

      result = CodePointer.analyze(timeline, [])

      pointer = List.first(result.stats.pointers)
      assert pointer.likely_location =~ "def handle_info"
    end

    test "deduplicates pointers by location" do
      timeline = %{
        timeline: [
          %{event: "render", view_module: MyApp.Live, sequence: 1},
          %{event: "render", view_module: MyApp.Live, sequence: 2},
          %{event: "render", view_module: MyApp.Live, sequence: 3}
        ]
      }

      result = CodePointer.analyze(timeline, [])

      # Should only have one pointer for render
      assert length(result.stats.pointers) == 1
    end

    test "handles empty timeline" do
      result = CodePointer.analyze(%{timeline: []}, [])

      assert result.stats.pointers == []
    end
  end
end
