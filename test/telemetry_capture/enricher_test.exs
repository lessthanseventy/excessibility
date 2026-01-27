defmodule Excessibility.TelemetryCapture.EnricherTest do
  use ExUnit.Case, async: true

  # Test implementation of enricher
  defmodule TestEnricher do
    @moduledoc false
    @behaviour Excessibility.TelemetryCapture.Enricher

    def name, do: :test

    def enrich(assigns, _opts) do
      %{test_field: Map.get(assigns, :value, 0) * 2}
    end
  end

  describe "enricher behaviour" do
    test "implements required callbacks" do
      assert function_exported?(TestEnricher, :name, 0)
      assert function_exported?(TestEnricher, :enrich, 2)
    end

    test "enrich returns map" do
      result = TestEnricher.enrich(%{value: 5}, [])
      assert is_map(result)
      assert result.test_field == 10
    end

    test "name returns atom" do
      assert TestEnricher.name() == :test
    end
  end
end
