defmodule Excessibility.TelemetryCapture.Analyzers.MemoryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.Memory

  describe "name/0" do
    test "returns :memory" do
      assert Memory.name() == :memory
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert Memory.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      timeline = build_timeline([1000, 2000, 3000])
      result = Memory.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
      assert is_list(result.findings)
    end

    test "calculates stats correctly" do
      timeline = build_timeline([1000, 2000, 3000, 4000])
      result = Memory.analyze(timeline, [])

      assert result.stats.min == 1000
      assert result.stats.max == 4000
      assert result.stats.avg == 2500
    end

    test "detects no issues in healthy timeline" do
      timeline = build_timeline([1000, 1100, 1200, 1300])
      result = Memory.analyze(timeline, [])

      assert Enum.empty?(result.findings)
    end

    test "detects large growth between events" do
      # 10x growth from event 1 to 2
      timeline = build_timeline([1000, 10_000, 11_000])
      result = Memory.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &(&1.severity in [:warning, :critical]))
      assert Enum.any?(result.findings, &String.contains?(&1.message, "grew"))
    end

    test "detects memory leak pattern" do
      # 3+ consecutive increases
      timeline = build_timeline([1000, 2000, 4000, 8000, 16_000])
      result = Memory.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &String.contains?(&1.message, "leak"))
    end

    test "handles single event timeline" do
      timeline = build_timeline([1000])
      result = Memory.analyze(timeline, [])

      assert Enum.empty?(result.findings)
      assert result.stats.min == 1000
      assert result.stats.max == 1000
    end

    test "handles empty timeline" do
      timeline = %{timeline: []}
      result = Memory.analyze(timeline, [])

      assert Enum.empty?(result.findings)
      assert result.stats == %{}
    end
  end

  # Helper to build test timeline
  defp build_timeline(memory_sizes) do
    timeline_entries =
      Enum.with_index(memory_sizes, 1)
      |> Enum.map(fn {size, seq} ->
        %{
          sequence: seq,
          event: "test_event",
          memory_size: size
        }
      end)

    %{timeline: timeline_entries}
  end
end
