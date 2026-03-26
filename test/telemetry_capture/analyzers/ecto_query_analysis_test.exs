defmodule Excessibility.TelemetryCapture.Analyzers.EctoQueryAnalysisTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Analyzers.EctoQueryAnalysis

  describe "name/0" do
    test "returns :ecto_query_analysis" do
      assert EctoQueryAnalysis.name() == :ecto_query_analysis
    end
  end

  describe "default_enabled?/0" do
    test "returns true" do
      assert EctoQueryAnalysis.default_enabled?() == true
    end
  end

  describe "requires_enrichers/0" do
    test "declares ecto_queries enricher dependency" do
      assert EctoQueryAnalysis.requires_enrichers() == [:ecto_queries]
    end
  end

  describe "analyze/2" do
    test "returns correct structure" do
      result = EctoQueryAnalysis.analyze(%{timeline: []}, [])

      assert is_map(result)
      assert Map.has_key?(result, :findings)
      assert Map.has_key?(result, :stats)
    end

    test "detects no issues with few queries" do
      timeline = %{
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            ecto_queries: [
              %{source: "users", operation: :select, duration_ms: 1.0, query: "SELECT"}
            ],
            ecto_query_count: 1,
            ecto_total_query_ms: 1.0
          }
        ]
      }

      result = EctoQueryAnalysis.analyze(timeline, [])
      assert result.findings == []
    end

    test "detects excessive queries per event" do
      queries =
        for _ <- 1..8,
            do: %{source: "products", operation: :select, duration_ms: 1.0, query: "SELECT * FROM products"}

      timeline = %{
        timeline: [
          %{sequence: 1, event: "handle_event:load", ecto_queries: queries, ecto_query_count: 8, ecto_total_query_ms: 8.0}
        ]
      }

      result = EctoQueryAnalysis.analyze(timeline, [])

      assert length(result.findings) > 0
      assert Enum.any?(result.findings, &(&1.severity in [:warning, :critical]))
    end

    test "detects N+1 pattern — multiple SELECTs on same table" do
      queries =
        for _ <- 1..15,
            do: %{source: "products", operation: :select, duration_ms: 1.0, query: "SELECT * FROM products WHERE id = $1"}

      timeline = %{
        timeline: [
          %{sequence: 1, event: "handle_event:load_items", ecto_queries: queries, ecto_query_count: 15, ecto_total_query_ms: 15.0}
        ]
      }

      result = EctoQueryAnalysis.analyze(timeline, [])

      assert length(result.findings) > 0
      n_plus_one_finding = Enum.find(result.findings, &(&1.metadata[:pattern] == :n_plus_one))
      assert n_plus_one_finding
      assert n_plus_one_finding.message =~ "products"
      assert n_plus_one_finding.message =~ "N+1"
    end

    test "detects slow queries" do
      timeline = %{
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            ecto_queries: [
              %{source: "reports", operation: :select, duration_ms: 150.0, query: "SELECT * FROM reports"}
            ],
            ecto_query_count: 1,
            ecto_total_query_ms: 150.0
          }
        ]
      }

      result = EctoQueryAnalysis.analyze(timeline, [])

      assert length(result.findings) > 0
      finding = List.first(result.findings)
      assert finding.message =~ "150"
    end

    test "detects slow total query time per event" do
      queries =
        for i <- 1..6,
            do: %{source: "table_#{i}", operation: :select, duration_ms: 100.0, query: "SELECT"}

      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", ecto_queries: queries, ecto_query_count: 6, ecto_total_query_ms: 600.0}
        ]
      }

      result = EctoQueryAnalysis.analyze(timeline, [])

      assert Enum.any?(result.findings, &(&1.message =~ "600"))
    end

    test "handles empty timeline" do
      result = EctoQueryAnalysis.analyze(%{timeline: []}, [])
      assert result.findings == []
      assert result.stats == %{}
    end

    test "handles timeline without ecto data" do
      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount"},
          %{sequence: 2, event: "render"}
        ]
      }

      result = EctoQueryAnalysis.analyze(timeline, [])
      assert result.findings == []
    end

    test "calculates query statistics" do
      queries = [
        %{source: "users", operation: :select, duration_ms: 2.0, query: "SELECT"},
        %{source: "products", operation: :select, duration_ms: 3.0, query: "SELECT"}
      ]

      timeline = %{
        timeline: [
          %{sequence: 1, event: "mount", ecto_queries: queries, ecto_query_count: 2, ecto_total_query_ms: 5.0},
          %{sequence: 2, event: "render", ecto_queries: [], ecto_query_count: 0, ecto_total_query_ms: 0}
        ]
      }

      result = EctoQueryAnalysis.analyze(timeline, [])

      assert Map.has_key?(result.stats, :total_queries)
      assert Map.has_key?(result.stats, :total_query_ms)
      assert result.stats.total_queries == 2
    end
  end
end
