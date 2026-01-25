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
end
