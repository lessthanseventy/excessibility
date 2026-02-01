defmodule Excessibility.MCP.Tools.ListAnalyzersTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.ListAnalyzers

  describe "name/0" do
    test "returns tool name" do
      assert ListAnalyzers.name() == "list_analyzers"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema" do
      schema = ListAnalyzers.input_schema()

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "include_opt_in")
    end
  end

  describe "execute/2" do
    test "returns list of all analyzers by default" do
      {:ok, result} = ListAnalyzers.execute(%{}, [])

      assert is_list(result["analyzers"])
      assert result["total"] > 0
      assert result["default_count"] > 0

      # Verify structure of each analyzer entry
      Enum.each(result["analyzers"], fn analyzer ->
        assert is_binary(analyzer["name"])
        assert is_boolean(analyzer["default_enabled"])
        assert is_binary(analyzer["description"])
        assert is_list(analyzer["detects"])
        assert is_list(analyzer["requires_enrichers"])
      end)
    end

    test "includes known analyzers" do
      {:ok, result} = ListAnalyzers.execute(%{}, [])

      names = Enum.map(result["analyzers"], & &1["name"])

      assert "memory" in names
      assert "performance" in names
      assert "data_growth" in names
      assert "event_pattern" in names
    end

    test "filters to default analyzers only" do
      {:ok, all_result} = ListAnalyzers.execute(%{"include_opt_in" => true}, [])
      {:ok, default_result} = ListAnalyzers.execute(%{"include_opt_in" => false}, [])

      # Default should be subset of all
      assert default_result["total"] <= all_result["total"]

      # All default analyzers should have default_enabled: true
      Enum.each(default_result["analyzers"], fn analyzer ->
        assert analyzer["default_enabled"] == true
      end)
    end

    test "returns correct counts" do
      {:ok, result} = ListAnalyzers.execute(%{}, [])

      assert result["total"] == length(result["analyzers"])
      assert result["default_count"] + result["opt_in_count"] == result["total"]

      # Verify counts match actual data
      default_count = Enum.count(result["analyzers"], & &1["default_enabled"])
      opt_in_count = Enum.count(result["analyzers"], &(not &1["default_enabled"]))

      assert result["default_count"] == default_count
      assert result["opt_in_count"] == opt_in_count
    end

    test "memory analyzer has correct structure" do
      {:ok, result} = ListAnalyzers.execute(%{}, [])

      memory = Enum.find(result["analyzers"], &(&1["name"] == "memory"))

      assert memory["default_enabled"] == true
      assert is_binary(memory["description"])
      assert String.length(memory["description"]) > 0
      assert "memory" in memory["requires_enrichers"]
    end
  end
end
