defmodule Excessibility.TelemetryCapture.Enrichers.AssignSizesTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.AssignSizes

  describe "name/0" do
    test "returns :assign_sizes" do
      assert AssignSizes.name() == :assign_sizes
    end
  end

  describe "cost/0" do
    test "returns :expensive" do
      assert AssignSizes.cost() == :expensive
    end
  end

  describe "enrich/2" do
    test "returns map with assign_sizes, total_memory, and largest_assign" do
      assigns = %{user: "test", count: 5}
      result = AssignSizes.enrich(assigns, [])

      assert is_map(result)
      assert is_map(result.assign_sizes)
      assert is_integer(result.total_memory)
      assert result.total_memory > 0
      assert is_tuple(result.largest_assign)
    end

    test "tracks per-assign byte sizes" do
      assigns = %{small: 1, large: String.duplicate("x", 1000)}
      result = AssignSizes.enrich(assigns, [])

      assert result.assign_sizes[:large] > result.assign_sizes[:small]
    end

    test "total_memory is sum of assign sizes" do
      assigns = %{a: 1, b: 2}
      result = AssignSizes.enrich(assigns, [])

      sum = result.assign_sizes |> Map.values() |> Enum.sum()
      assert result.total_memory == sum
    end

    test "largest_assign identifies the biggest assign" do
      assigns = %{small: 1, large: String.duplicate("x", 1000)}
      result = AssignSizes.enrich(assigns, [])

      {key, _size} = result.largest_assign
      assert key == :large
    end

    test "handles empty assigns" do
      result = AssignSizes.enrich(%{}, [])
      assert result.assign_sizes == %{}
      assert result.total_memory == 0
      assert result.largest_assign == nil
    end

    test "skips Phoenix internal keys" do
      assigns = %{flash: %{}, __changed__: %{}, real_data: "hello"}
      result = AssignSizes.enrich(assigns, [])

      refute Map.has_key?(result.assign_sizes, :flash)
      refute Map.has_key?(result.assign_sizes, :__changed__)
      assert Map.has_key?(result.assign_sizes, :real_data)
    end
  end
end
