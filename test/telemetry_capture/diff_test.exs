defmodule Excessibility.TelemetryCapture.DiffTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Diff

  describe "compute_diff/2" do
    test "returns nil when previous is nil" do
      current = %{user_id: 123}
      result = Diff.compute_diff(current, nil)

      assert result == nil
    end

    test "detects added keys" do
      previous = %{user_id: 123}
      current = %{user_id: 123, cart_items: 1}

      result = Diff.compute_diff(current, previous)

      assert result.added == %{cart_items: 1}
      assert result.changed == %{}
      assert result.removed == []
    end

    test "detects removed keys" do
      previous = %{user_id: 123, temp: "value"}
      current = %{user_id: 123}

      result = Diff.compute_diff(current, previous)

      assert result.added == %{}
      assert result.changed == %{}
      assert result.removed == [:temp]
    end

    test "detects changed values" do
      previous = %{status: :pending, count: 0}
      current = %{status: :complete, count: 5}

      result = Diff.compute_diff(current, previous)

      assert result.added == %{}

      assert result.changed == %{
               "status" => {:pending, :complete},
               "count" => {0, 5}
             }

      assert result.removed == []
    end

    test "handles nested maps" do
      previous = %{user: %{id: 1, name: "Old"}}
      current = %{user: %{id: 1, name: "New"}}

      result = Diff.compute_diff(current, previous)

      assert result.changed == %{
               "user.name" => {"Old", "New"}
             }
    end
  end

  describe "extract_changes/1" do
    test "converts diff to simple change map" do
      diff = %{
        added: %{new_field: "value"},
        changed: %{"status" => {:old, :new}},
        removed: [:temp]
      }

      result = Diff.extract_changes(diff)

      assert result == %{
               "new_field" => {nil, "value"},
               "status" => {:old, :new}
             }
    end

    test "returns nil for nil diff" do
      assert Diff.extract_changes(nil) == nil
    end
  end
end
