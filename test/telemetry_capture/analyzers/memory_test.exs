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

  describe "requires_enrichers/0" do
    test "declares memory enricher dependency" do
      assert Memory.requires_enrichers() == [:assign_sizes]
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
      # 10x growth from event 1 to 2, above the absolute floor (issue #142:
      # a ratio off a tiny heap is noise, so sizes must clear a few hundred KB)
      timeline = build_timeline([300_000, 3_000_000, 3_300_000])
      result = Memory.analyze(timeline, [])

      assert result.findings != []
      assert Enum.any?(result.findings, &(&1.severity in [:warning, :critical]))
      assert Enum.any?(result.findings, &String.contains?(&1.message, "grew"))
    end

    test "detects memory leak pattern" do
      # 3+ consecutive increases past the absolute floor (issue #142)
      timeline = build_timeline([300_000, 600_000, 1_200_000, 2_400_000, 4_800_000])
      result = Memory.analyze(timeline, [])

      assert result.findings != []
      assert Enum.any?(result.findings, &String.contains?(&1.message, "leak"))
    end

    test "a flat plateau at a large size is not growth (issue #146)" do
      # A run of small events that jumps once to ~300 KB and then holds steady.
      # The jump (events 10->11) is a real finding; the flat 300 KB -> 300 KB
      # transition must not be reported as "grew 1.0x" just because 300 KB is a
      # global outlier that clears the absolute floor.
      timeline = build_timeline(List.duplicate(1_000, 10) ++ [300_000, 300_000])
      result = Memory.analyze(timeline, [])

      # The real jump is still flagged.
      assert Enum.any?(result.findings, &(&1.events == [10, 11]))

      # No finding describes a flat transition.
      refute Enum.any?(result.findings, &String.contains?(&1.message, "grew 1.0x")),
             "flat plateau reported as growth: #{inspect(Enum.map(result.findings, & &1.message))}"

      refute Enum.any?(result.findings, &(&1.events == [11, 12])),
             "flat transition flagged: #{inspect(result.findings)}"
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
      memory_sizes
      |> Enum.with_index(1)
      |> Enum.map(fn {size, seq} ->
        %{
          sequence: seq,
          event: "test_event",
          total_memory: size
        }
      end)

    %{timeline: timeline_entries}
  end
end
