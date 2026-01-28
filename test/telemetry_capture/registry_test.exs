defmodule Excessibility.TelemetryCapture.RegistryTest do
  use ExUnit.Case, async: false

  alias Excessibility.TelemetryCapture.Registry

  # Clean up custom config after each test
  setup do
    on_exit(fn ->
      Application.delete_env(:excessibility, :custom_enrichers)
      Application.delete_env(:excessibility, :custom_analyzers)
    end)

    :ok
  end

  describe "discover_enrichers/0" do
    test "returns list of enricher modules" do
      enrichers = Registry.discover_enrichers()
      assert is_list(enrichers)
    end

    test "includes built-in enrichers" do
      enrichers = Registry.discover_enrichers()
      assert Excessibility.TelemetryCapture.Enrichers.Memory in enrichers
    end

    test "includes custom enrichers from config" do
      Application.put_env(:excessibility, :custom_enrichers, [TestCustomEnricher])

      enrichers = Registry.discover_enrichers()
      assert TestCustomEnricher in enrichers
    end

    test "filters out modules that don't implement Enricher behaviour" do
      # String is a valid module but doesn't implement Enricher
      Application.put_env(:excessibility, :custom_enrichers, [String])

      enrichers = Registry.discover_enrichers()
      refute String in enrichers
    end

    test "filters out non-existent modules" do
      Application.put_env(:excessibility, :custom_enrichers, [NonExistentModule])

      enrichers = Registry.discover_enrichers()
      refute NonExistentModule in enrichers
    end

    test "returns sorted list by name" do
      enrichers = Registry.discover_enrichers()
      names = Enum.map(enrichers, & &1.name())
      assert names == Enum.sort(names)
    end
  end

  describe "discover_analyzers/0" do
    test "returns list of analyzer modules" do
      analyzers = Registry.discover_analyzers()
      assert is_list(analyzers)
    end

    test "includes built-in analyzers" do
      analyzers = Registry.discover_analyzers()
      assert Excessibility.TelemetryCapture.Analyzers.Memory in analyzers
    end

    test "includes custom analyzers from config" do
      Application.put_env(:excessibility, :custom_analyzers, [TestCustomAnalyzer])

      analyzers = Registry.discover_analyzers()
      assert TestCustomAnalyzer in analyzers
    end

    test "filters out modules that don't implement Analyzer behaviour" do
      # String is a valid module but doesn't implement Analyzer
      Application.put_env(:excessibility, :custom_analyzers, [String])

      analyzers = Registry.discover_analyzers()
      refute String in analyzers
    end

    test "filters out non-existent modules" do
      Application.put_env(:excessibility, :custom_analyzers, [NonExistentModule])

      analyzers = Registry.discover_analyzers()
      refute NonExistentModule in analyzers
    end

    test "returns sorted list by name" do
      analyzers = Registry.discover_analyzers()
      names = Enum.map(analyzers, & &1.name())
      assert names == Enum.sort(names)
    end
  end

  describe "get_default_analyzers/0" do
    test "returns only analyzers with default_enabled? = true" do
      defaults = Registry.get_default_analyzers()
      assert is_list(defaults)

      # All returned analyzers should have default_enabled? = true
      Enum.each(defaults, fn analyzer ->
        assert analyzer.default_enabled?() == true
      end)
    end

    test "includes custom analyzers that are default enabled" do
      Application.put_env(:excessibility, :custom_analyzers, [TestCustomAnalyzer])

      defaults = Registry.get_default_analyzers()
      # TestCustomAnalyzer has default_enabled? = true
      assert TestCustomAnalyzer in defaults
    end
  end

  describe "get_all_analyzers/0" do
    test "returns all registered analyzers" do
      all = Registry.get_all_analyzers()
      defaults = Registry.get_default_analyzers()

      # All defaults should be in the complete list
      assert Enum.all?(defaults, &(&1 in all))
    end
  end

  describe "get_analyzer/1" do
    test "returns nil for unknown analyzer" do
      assert Registry.get_analyzer(:nonexistent) == nil
    end

    test "finds custom analyzer by name" do
      Application.put_env(:excessibility, :custom_analyzers, [TestCustomAnalyzer])

      assert Registry.get_analyzer(:test_custom) == TestCustomAnalyzer
    end
  end

  describe "get_enricher/1" do
    test "returns nil for unknown enricher" do
      assert Registry.get_enricher(:nonexistent) == nil
    end

    test "finds built-in enricher by name" do
      assert Registry.get_enricher(:memory) == Excessibility.TelemetryCapture.Enrichers.Memory
    end

    test "finds custom enricher by name" do
      Application.put_env(:excessibility, :custom_enrichers, [TestCustomEnricher])

      assert Registry.get_enricher(:test_custom) == TestCustomEnricher
    end
  end

  describe "resolve_enrichers/1" do
    test "returns enrichers needed by given analyzer names" do
      enrichers = Registry.resolve_enrichers([:memory, :performance])

      assert :memory in enrichers
      assert :duration in enrichers
    end

    test "deduplicates enrichers" do
      # If two analyzers needed the same enricher, only include once
      enrichers = Registry.resolve_enrichers([:memory, :memory])

      assert length(Enum.filter(enrichers, &(&1 == :memory))) == 1
    end

    test "returns empty list for analyzers with no dependencies" do
      enrichers = Registry.resolve_enrichers([:event_pattern])

      assert enrichers == []
    end

    test "handles unknown analyzer names gracefully" do
      enrichers = Registry.resolve_enrichers([:memory, :nonexistent])

      assert :memory in enrichers
    end

    test "returns empty list for empty input" do
      enrichers = Registry.resolve_enrichers([])

      assert enrichers == []
    end
  end
end

# Test fixtures for custom plugins
defmodule TestCustomEnricher do
  @moduledoc false
  @behaviour Excessibility.TelemetryCapture.Enricher

  def name, do: :test_custom

  def enrich(_assigns, _opts) do
    %{test_field: "test_value"}
  end
end

defmodule TestCustomAnalyzer do
  @moduledoc false
  @behaviour Excessibility.TelemetryCapture.Analyzer

  def name, do: :test_custom
  def default_enabled?, do: true

  def analyze(_timeline, _opts) do
    %{findings: [], stats: %{}}
  end
end
