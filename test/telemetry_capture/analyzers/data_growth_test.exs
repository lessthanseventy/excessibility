defmodule Excessibility.TelemetryCapture.Analyzers.DataGrowthTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.DataGrowth

  describe "name/0" do
    test "returns :data_growth" do
      assert DataGrowth.name() == :data_growth
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert DataGrowth.default_enabled?() == true
    end
  end

  describe "analyze/2" do
    test "returns map with findings and stats" do
      timeline = %{timeline: []}

      result = DataGrowth.analyze(timeline, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects no issues with stable list sizes" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{products: 10}},
          %{sequence: 2, event: "handle_event", list_sizes: %{products: 10}},
          %{sequence: 3, event: "handle_event", list_sizes: %{products: 10}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      assert result.findings == []
    end

    test "detects unbounded list growth" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{products: 10}},
          %{sequence: 2, event: "handle_event", list_sizes: %{products: 50}},
          %{sequence: 3, event: "handle_event", list_sizes: %{products: 200}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      assert length(result.findings) > 0
      growth_finding = List.first(result.findings)
      assert growth_finding.severity in [:warning, :critical]
      assert growth_finding.message =~ "products"
      assert growth_finding.message =~ ~r/(grow|pagination)/
    end

    test "detects rapid growth (10x)" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{items: 5}},
          %{sequence: 2, event: "handle_event", list_sizes: %{items: 50}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.severity == :critical
      assert finding.message =~ "10"
    end

    test "tracks multiple lists independently" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{products: 10, users: 5}},
          %{sequence: 2, event: "handle_event", list_sizes: %{products: 100, users: 5}},
          %{sequence: 3, event: "handle_event", list_sizes: %{products: 100, users: 50}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      # Should detect growth in both products and users
      assert length(result.findings) >= 2
      messages = Enum.map(result.findings, & &1.message)
      assert Enum.any?(messages, &String.contains?(&1, "products"))
      assert Enum.any?(messages, &String.contains?(&1, "users"))
    end

    test "suggests pagination for large growing lists" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{products: 50}},
          %{sequence: 2, event: "handle_event", list_sizes: %{products: 150}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      pagination_suggestion? =
        Enum.any?(result.findings, fn f ->
          String.contains?(f.message, "pagination") or
            String.contains?(f.message, "lazy")
        end)

      assert pagination_suggestion?
    end

    test "calculates growth statistics" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{items: 10}},
          %{sequence: 2, event: "handle_event", list_sizes: %{items: 30}},
          %{sequence: 3, event: "handle_event", list_sizes: %{items: 50}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      assert Map.has_key?(result.stats, :growing_lists)
      assert is_list(result.stats.growing_lists)
    end

    test "handles empty timeline" do
      timeline = %{timeline: []}

      result = DataGrowth.analyze(timeline, [])

      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles timeline without list size data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "handle_event"}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      # Should not crash
      assert result.findings == []
    end

    test "ignores lists that shrink" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{products: 100}},
          %{sequence: 2, event: "handle_event", list_sizes: %{products: 50}},
          %{sequence: 3, event: "handle_event", list_sizes: %{products: 10}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      # Shrinking lists are not a problem
      assert result.findings == []
    end

    test "detects growth in nested list paths" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{"cart.items": 5}},
          %{sequence: 2, event: "handle_event", list_sizes: %{"cart.items": 50}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.message =~ "cart.items"
    end

    test "includes growth multiplier in metadata" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", list_sizes: %{items: 10}},
          %{sequence: 2, event: "handle_event", list_sizes: %{items: 50}}
        ]
      }

      result = DataGrowth.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert Map.has_key?(finding.metadata, :growth_multiplier)
      assert finding.metadata.growth_multiplier == 5.0
    end
  end
end
