defmodule Excessibility.TelemetryCapture.RegistryTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Registry

  describe "discover_enrichers/0" do
    test "returns list of enricher modules" do
      enrichers = Registry.discover_enrichers()
      assert is_list(enrichers)
    end
  end

  describe "discover_analyzers/0" do
    test "returns list of analyzer modules" do
      analyzers = Registry.discover_analyzers()
      assert is_list(analyzers)
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
  end
end
