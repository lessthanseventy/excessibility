defmodule Excessibility.MCP.Resources.AnalyzerTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Resources.Analyzer

  describe "uri_pattern/0" do
    test "returns analyzer URI pattern" do
      assert Analyzer.uri_pattern() == "analyzer://{name}"
    end
  end

  describe "name/0" do
    test "returns resource name" do
      assert Analyzer.name() == "analyzer"
    end
  end

  describe "mime_type/0" do
    test "returns markdown mime type" do
      assert Analyzer.mime_type() == "text/markdown"
    end
  end

  describe "list/0" do
    test "returns list of analyzer resources" do
      resources = Analyzer.list()

      assert is_list(resources)
      assert length(resources) > 0

      # Verify structure
      Enum.each(resources, fn resource ->
        assert Map.has_key?(resource, "uri")
        assert Map.has_key?(resource, "name")
        assert Map.has_key?(resource, "description")
        assert Map.has_key?(resource, "mimeType")
        assert resource["mimeType"] == "text/markdown"
        assert String.starts_with?(resource["uri"], "analyzer://")
      end)
    end

    test "includes known analyzers" do
      resources = Analyzer.list()
      names = Enum.map(resources, & &1["name"])

      assert "memory" in names
      assert "performance" in names
      assert "data_growth" in names
    end
  end

  describe "read/1" do
    test "returns documentation for memory analyzer" do
      {:ok, doc} = Analyzer.read("analyzer://memory")

      assert is_binary(doc)
      assert doc =~ "# Memory Analyzer"
      assert doc =~ "Default Enabled"
      assert doc =~ "Required Enrichers"
      assert doc =~ "What It Detects"
      assert doc =~ "How to Fix"
      assert doc =~ "Examples"
      assert doc =~ "Usage"
      assert doc =~ "mix excessibility.debug"
    end

    test "returns documentation for performance analyzer" do
      {:ok, doc} = Analyzer.read("analyzer://performance")

      assert doc =~ "# Performance Analyzer"
      assert doc =~ "duration"
    end

    test "returns error for unknown analyzer" do
      {:error, message} = Analyzer.read("analyzer://nonexistent")

      assert message =~ "not found"
    end

    test "returns error for invalid URI" do
      {:error, message} = Analyzer.read("invalid://uri")

      assert message =~ "Invalid"
    end
  end

  describe "documentation content" do
    test "memory analyzer includes fix examples" do
      {:ok, doc} = Analyzer.read("analyzer://memory")

      assert doc =~ "stream"
      assert doc =~ "limit"
    end

    test "documentation includes usage instructions" do
      {:ok, doc} = Analyzer.read("analyzer://memory")

      assert doc =~ "--analyze=memory"
      assert doc =~ "--analyze=all"
    end
  end
end
