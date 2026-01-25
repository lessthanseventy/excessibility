defmodule Excessibility.TelemetryCapture.FormatterTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Formatter

  describe "format_json/1" do
    test "encodes timeline as JSON" do
      timeline = %{
        test: "my_test",
        duration_ms: 500,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{user_id: 123},
            changes: nil
          }
        ]
      }

      result = Formatter.format_json(timeline)

      assert is_binary(result)
      decoded = Jason.decode!(result)
      assert decoded["test"] == "my_test"
      assert decoded["duration_ms"] == 500
      assert length(decoded["timeline"]) == 1
    end

    test "converts tuples to lists for JSON compatibility" do
      timeline = %{
        test: "test",
        duration_ms: 100,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{status: :pending},
            changes: %{"status" => {:pending, :complete}}
          }
        ]
      }

      result = Formatter.format_json(timeline)

      decoded = Jason.decode!(result)
      first_event = List.first(decoded["timeline"])
      # Tuple {old, new} becomes list [old, new] in JSON
      assert first_event["changes"]["status"] == ["pending", "complete"]
    end
  end

  describe "format_markdown/2" do
    test "generates markdown with timeline table" do
      timeline = %{
        test: "purchase_flow",
        duration_ms: 850,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00.000Z],
            key_state: %{user_id: 123, cart_items_count: 0},
            changes: nil,
            duration_since_previous_ms: nil
          },
          %{
            sequence: 2,
            event: "handle_event:add_to_cart",
            timestamp: ~U[2026-01-25 10:00:00.350Z],
            key_state: %{user_id: 123, cart_items_count: 1},
            changes: %{"cart_items_count" => {0, 1}},
            duration_since_previous_ms: 350
          }
        ]
      }

      result = Formatter.format_markdown(timeline, [])

      assert result =~ "# Test Debug Report: purchase_flow"
      assert result =~ "850ms"
      assert result =~ "| # | Time | Event | Key Changes |"
      assert result =~ "| 1 | +0ms | mount |"
      assert result =~ "| 2 | +350ms | handle_event:add_to_cart | cart_items_count: 0→1 |"
    end

    test "generates detailed change sections" do
      timeline = %{
        test: "test",
        duration_ms: 100,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            timestamp: ~U[2026-01-25 10:00:00Z],
            key_state: %{status: :pending},
            changes: nil,
            duration_since_previous_ms: nil
          },
          %{
            sequence: 2,
            event: "submit",
            timestamp: ~U[2026-01-25 10:00:00.100Z],
            key_state: %{status: :complete},
            changes: %{"status" => {:pending, :complete}},
            duration_since_previous_ms: 100
          }
        ]
      }

      result = Formatter.format_markdown(timeline, [])

      assert result =~ "## Detailed Changes"
      assert result =~ "### Event 2: submit (+100ms)"
      assert result =~ "**State Changes:**"
      assert result =~ "- `status`: :pending → :complete"
    end
  end
end
