defmodule Excessibility.TelemetryCapture.TimelineTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Timeline

  describe "extract_key_state/2" do
    test "extracts small primitive values" do
      assigns = %{
        user_id: 123,
        status: :active,
        name: "John",
        large_text: String.duplicate("a", 500)
      }

      result = Timeline.extract_key_state(assigns)

      assert result.user_id == 123
      assert result.status == :active
      assert result.name == "John"
      refute Map.has_key?(result, :large_text)
    end

    test "extracts highlighted fields from config" do
      assigns = %{
        current_user: %{id: 123},
        errors: ["error"],
        other: "ignored"
      }

      result = Timeline.extract_key_state(assigns, [:current_user, :errors])

      assert result.current_user == %{id: 123}
      assert result.errors == ["error"]
      refute Map.has_key?(result, :other)
    end

    test "converts lists to counts" do
      assigns = %{
        products: [%{id: 1}, %{id: 2}, %{id: 3}],
        tags: []
      }

      result = Timeline.extract_key_state(assigns)

      assert result.products_count == 3
      assert result.tags_count == 0
    end

    test "extracts live_action" do
      assigns = %{
        live_action: :edit,
        other: "data"
      }

      result = Timeline.extract_key_state(assigns)

      assert result.live_action == :edit
    end
  end

  describe "build_timeline/2" do
    test "builds timeline from snapshots" do
      snapshots = [
        %{
          event_type: "mount",
          assigns: %{user_id: 123, products_count: 0},
          timestamp: ~U[2026-01-25 10:00:00Z],
          view_module: MyApp.Live
        },
        %{
          event_type: "handle_event:add",
          assigns: %{user_id: 123, products_count: 1},
          timestamp: ~U[2026-01-25 10:00:01Z],
          view_module: MyApp.Live
        }
      ]

      result = Timeline.build_timeline(snapshots, "test_name")

      assert result.test == "test_name"
      assert result.duration_ms == 1000
      assert length(result.timeline) == 2

      first = Enum.at(result.timeline, 0)
      assert first.sequence == 1
      assert first.event == "mount"
      assert first.changes == nil

      second = Enum.at(result.timeline, 1)
      assert second.sequence == 2
      assert second.event == "handle_event:add"
      assert second.changes == %{"products_count" => {0, 1}}
      assert second.duration_since_previous_ms == 1000
    end

    test "handles empty snapshots" do
      result = Timeline.build_timeline([], "empty_test")

      assert result.test == "empty_test"
      assert result.timeline == []
      assert result.duration_ms == 0
    end
  end

  describe "enricher integration" do
    test "build_timeline_entry includes enriched data" do
      snapshot = %{
        event_type: "mount",
        assigns: %{user: "test", count: 5},
        timestamp: ~U[2024-01-01 00:00:00Z],
        view_module: TestModule
      }

      entry = Timeline.build_timeline_entry(snapshot, nil, 1, [])

      # Should have memory_size from Memory enricher
      assert Map.has_key?(entry, :memory_size)
      assert is_integer(entry.memory_size)
      assert entry.memory_size > 0
    end

    test "enrichments are merged with timeline entry" do
      snapshot = %{
        event_type: "handle_event:click",
        assigns: %{data: "value"},
        timestamp: ~U[2024-01-01 00:00:01Z],
        view_module: TestModule
      }

      entry = Timeline.build_timeline_entry(snapshot, nil, 2, [])

      # Original fields still present
      assert entry.sequence == 2
      assert entry.event == "handle_event:click"
      assert entry.view_module == TestModule

      # Enriched field added
      assert Map.has_key?(entry, :memory_size)
    end
  end
end
