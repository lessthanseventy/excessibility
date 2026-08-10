defmodule Excessibility.Review.BehavioralTest do
  use ExUnit.Case, async: true

  alias Excessibility.Review.Behavioral
  alias Excessibility.TelemetryCapture.Registry

  # A stand-in analyzer so the test doesn't depend on a realistic timeline.
  defmodule StubAnalyzer do
    @moduledoc false
    @behaviour Excessibility.TelemetryCapture.Analyzer

    @impl true
    def name, do: :stub

    @impl true
    def default_enabled?, do: false

    @impl true
    def analyze(_timeline, _opts) do
      %{
        findings: [
          %{severity: :critical, message: "N+1 query in orders list", events: [3], metadata: %{}},
          %{severity: :info, message: "assign :cart never changes", events: [1], metadata: %{}}
        ],
        stats: %{}
      }
    end
  end

  test "runs the given analyzers and normalizes their findings" do
    findings = Behavioral.findings(%{timeline: []}, analyzers: [StubAnalyzer])

    assert [critical, info] = findings
    assert critical.rule == :stub
    assert critical.source == :telemetry
    # analyzer :critical maps to the review :serious scale
    assert critical.severity == :serious
    assert critical.message =~ "N+1"
    assert critical.events == [3]
    # analyzer :info maps to :minor
    assert info.severity == :minor
  end

  test "returns an empty list when no analyzers produce findings" do
    defmodule QuietAnalyzer do
      @moduledoc false
      @behaviour Excessibility.TelemetryCapture.Analyzer

      @impl true
      def name, do: :quiet
      @impl true
      def default_enabled?, do: false
      @impl true
      def analyze(_timeline, _opts), do: %{findings: [], stats: %{}}
    end

    assert Behavioral.findings(%{}, analyzers: [QuietAnalyzer]) == []
  end

  describe "resilience to analyzer-filtered timelines (#158)" do
    # A timeline as produced by `mix excessibility.debug --analyze=ecto_query_analysis`:
    # ecto fields are present, but the memory/duration enricher fields are not.
    defp ecto_only_timeline do
      %{
        test: "PageLiveTest: filtered",
        timeline: [
          %{sequence: 1, event: "mount", view_module: "PageLive", ecto_queries: [], ecto_query_count: 0},
          %{
            sequence: 2,
            event: "handle_event:save",
            view_module: "PageLive",
            ecto_queries: [
              %{source: "categories", operation: "select", duration_ms: 1.0, query: "SELECT ..."}
            ],
            ecto_query_count: 1
          }
        ]
      }
    end

    test "a filtered timeline does not crash the default analyzer set" do
      # Regression: memory analyzer read event.total_memory directly and raised
      # KeyError, so review emitted no result at all.
      result = Behavioral.analyze(ecto_only_timeline(), [])
      assert is_list(result.findings)
    end

    test "skipped analyzers are surfaced as explicit value-free warnings" do
      result = Behavioral.analyze(ecto_only_timeline(), [])

      # memory requires the :assign_sizes enricher (total_memory), absent here.
      assert Enum.any?(result.warnings, &(&1 =~ "memory" and &1 =~ "skipped"))
      # ecto_query_analysis's enricher IS present, so it is not skipped.
      refute Enum.any?(result.warnings, &(&1 =~ "ecto_query_analysis" and &1 =~ "skipped"))
    end

    test "findings/2 returns a plain list and never raises on a filtered timeline" do
      assert is_list(Behavioral.findings(ecto_only_timeline(), []))
    end

    test "a full-enricher timeline runs the memory analyzer (not skipped)" do
      full = %{
        test: "t",
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            view_module: "PageLive",
            total_memory: 1_000,
            assign_sizes: %{"a" => 1_000},
            list_sizes: %{},
            state_keys: [],
            component_count: 0,
            push_events: [],
            ecto_queries: [],
            event_duration_ms: 1
          }
        ]
      }

      result = Behavioral.analyze(full, [])
      refute Enum.any?(result.warnings, &(&1 =~ "memory" and &1 =~ "skipped"))
    end

    test "every default analyzer is valid review input on a minimally-enriched timeline" do
      # A `mix excessibility.debug --analyze=<one>` run emits only that analyzer's
      # enrichers; the review must remain valid input for any such filtered set.
      # Run each default analyzer alone against a bare timeline: it is either
      # skipped (its enricher is absent) or tolerates the missing fields — never
      # a hard exception.
      bare = %{
        test: "t",
        timeline: [
          %{sequence: 1, event: "mount", view_module: "PageLive"},
          %{sequence: 2, event: "handle_event:save", view_module: "PageLive"}
        ]
      }

      for analyzer <- Registry.get_default_analyzers() do
        result = Behavioral.analyze(bare, analyzers: [analyzer])
        assert is_list(result.findings), "#{analyzer.name()} did not emit a findings list"
        assert is_list(result.warnings)
      end
    end
  end
end
