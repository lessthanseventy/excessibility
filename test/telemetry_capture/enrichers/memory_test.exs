defmodule Excessibility.TelemetryCapture.Enrichers.MemoryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.Memory

  describe "name/0" do
    test "returns :memory" do
      assert Memory.name() == :memory
    end
  end

  describe "enrich/2" do
    test "returns map with memory_size key" do
      assigns = %{user: "test", count: 5}
      result = Memory.enrich(assigns, [])

      assert is_map(result)
      assert Map.has_key?(result, :memory_size)
      assert is_integer(result.memory_size)
      assert result.memory_size > 0
    end

    test "calculates size for empty assigns" do
      result = Memory.enrich(%{}, [])
      assert result.memory_size > 0
    end

    test "size increases with more data" do
      small = Memory.enrich(%{a: 1}, [])
      large = Memory.enrich(%{a: 1, b: 2, c: 3, d: 4, e: 5}, [])

      assert large.memory_size > small.memory_size
    end

    test "size increases with larger values" do
      small = Memory.enrich(%{text: "hi"}, [])
      large = Memory.enrich(%{text: String.duplicate("x", 1000)}, [])

      assert large.memory_size > small.memory_size
    end

    test "handles nested maps" do
      assigns = %{
        user: %{name: "Alice", age: 30},
        items: [1, 2, 3]
      }

      result = Memory.enrich(assigns, [])
      assert result.memory_size > 0
    end
  end
end
