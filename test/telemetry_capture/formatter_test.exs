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
  end
end
