defmodule Excessibility.TelemetryCapture.IntegrationTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture.Registry

  describe "enricher discovery" do
    test "all enrichers are discoverable" do
      enrichers = Registry.discover_enrichers()

      expected =
        ~w(binary_content changeset collection_size component_tree duration memory query staleness state)a

      actual = enrichers |> Enum.map(& &1.name()) |> Enum.sort()

      for name <- expected do
        assert name in actual, "Missing enricher: #{name}"
      end
    end

    test "enrichers return valid maps" do
      assigns = %{user: "test", items: [1, 2, 3], count: 5}

      for enricher <- Registry.discover_enrichers() do
        result = enricher.enrich(assigns, [])
        assert is_map(result), "#{enricher.name()} did not return a map"
      end
    end

    test "enrichers handle empty assigns" do
      for enricher <- Registry.discover_enrichers() do
        result = enricher.enrich(%{}, [])
        assert is_map(result), "#{enricher.name()} failed on empty assigns"
      end
    end
  end

  describe "analyzer discovery" do
    test "all analyzers are discoverable" do
      analyzers = Registry.discover_analyzers()

      expected =
        ~w(
          accessibility_correlation assign_lifecycle cascade_effect code_pointer
          data_growth event_pattern form_validation handle_event_noop hypothesis
          memory n_plus_one performance render_efficiency state_machine summary
        )a

      actual = analyzers |> Enum.map(& &1.name()) |> Enum.sort()

      for name <- expected do
        assert name in actual, "Missing analyzer: #{name}"
      end
    end

    test "analyzers return valid structure" do
      timeline = %{
        test: "test.exs",
        duration_ms: 100,
        timeline: [
          %{
            sequence: 1,
            event: "mount",
            memory_size: 1000,
            changes: nil,
            key_state: %{a: 1},
            view_module: TestModule,
            timestamp: 0
          }
        ]
      }

      for analyzer <- Registry.discover_analyzers() do
        result = analyzer.analyze(timeline, [])
        assert Map.has_key?(result, :findings), "#{analyzer.name()} missing :findings"
        assert Map.has_key?(result, :stats), "#{analyzer.name()} missing :stats"
        assert is_list(result.findings), "#{analyzer.name()} :findings not a list"
        assert is_map(result.stats), "#{analyzer.name()} :stats not a map"
      end
    end

    test "analyzers handle empty timeline" do
      timeline = %{test: "test.exs", duration_ms: 0, timeline: []}

      for analyzer <- Registry.discover_analyzers() do
        result = analyzer.analyze(timeline, [])
        assert is_map(result), "#{analyzer.name()} failed on empty timeline"
      end
    end

    test "default analyzers are a subset of all analyzers" do
      all = MapSet.new(Registry.discover_analyzers(), & &1.name())
      defaults = MapSet.new(Registry.get_default_analyzers(), & &1.name())

      assert MapSet.subset?(defaults, all),
             "Default analyzers include unknown: #{inspect(MapSet.difference(defaults, all))}"
    end
  end

  describe "enricher-analyzer integration" do
    test "timeline with enrichments feeds analyzers correctly" do
      alias Excessibility.TelemetryCapture.Timeline

      # Create mock snapshots
      snapshots = [
        %{
          event_type: "mount",
          assigns: %{count: 0, items: []},
          timestamp: DateTime.utc_now(),
          view_module: TestModule,
          measurements: %{}
        },
        %{
          event_type: "render",
          assigns: %{count: 1, items: [1]},
          timestamp: DateTime.add(DateTime.utc_now(), 100, :millisecond),
          view_module: TestModule,
          measurements: %{}
        }
      ]

      # Build timeline with enrichments
      timeline = Timeline.build_timeline(snapshots, "integration_test.exs", [])

      # Verify timeline has enrichment fields
      first_entry = List.first(timeline.timeline)
      assert Map.has_key?(first_entry, :memory_size), "Missing memory_size enrichment"
      assert Map.has_key?(first_entry, :state_keys), "Missing state_keys enrichment"

      # Run all analyzers on enriched timeline
      for analyzer <- Registry.discover_analyzers() do
        result = analyzer.analyze(timeline, [])
        assert is_map(result), "#{analyzer.name()} failed on enriched timeline"
      end
    end
  end

  describe "plugin costs" do
    test "enrichers can declare cost" do
      alias Excessibility.TelemetryCapture.Enricher

      for enricher <- Registry.discover_enrichers() do
        cost = Enricher.get_cost(enricher)
        assert cost in [:cheap, :moderate, :expensive], "#{enricher.name()} has invalid cost: #{cost}"
      end
    end
  end

  describe "analyzer dependencies" do
    test "analyzers can declare dependencies" do
      alias Excessibility.TelemetryCapture.Analyzer

      for analyzer <- Registry.discover_analyzers() do
        deps = Analyzer.get_dependencies(analyzer)
        assert is_list(deps), "#{analyzer.name()} dependencies should be a list"
      end
    end

    test "sort_by_dependencies preserves all analyzers" do
      alias Excessibility.TelemetryCapture.Analyzer

      analyzers = Registry.discover_analyzers()
      sorted = Analyzer.sort_by_dependencies(analyzers)

      assert length(sorted) == length(analyzers),
             "Sorted list has different length than input"

      sorted_names = MapSet.new(sorted, & &1.name())
      original_names = MapSet.new(analyzers, & &1.name())

      assert MapSet.equal?(sorted_names, original_names),
             "Sorted list has different analyzers than input"
    end
  end
end
