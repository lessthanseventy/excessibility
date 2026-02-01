defmodule Excessibility.MCP.Tools.ExplainIssueTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.ExplainIssue

  describe "name/0" do
    test "returns tool name" do
      assert ExplainIssue.name() == "explain_issue"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema with required issue" do
      schema = ExplainIssue.input_schema()

      assert schema["type"] == "object"
      assert schema["required"] == ["issue"]
      assert Map.has_key?(schema["properties"], "issue")
    end
  end

  describe "execute/2 with WCAG codes" do
    test "explains H37 (alt text)" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "H37"}, [])

      assert result["issue"] == "H37"
      assert result["title"] == "Images must have alt attributes"
      assert result["wcag"] =~ "1.1.1"
      assert is_binary(result["why"])
      assert length(result["phoenix_patterns"]) > 0
      assert is_map(result["examples"])
      assert Map.has_key?(result["examples"], "bad")
      assert Map.has_key?(result["examples"], "good")
      assert "H36" in result["related"]
    end

    test "explains H44 (form labels)" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "H44"}, [])

      assert result["issue"] == "H44"
      assert result["title"] == "Form inputs must have associated labels"
      assert result["wcag"] =~ "1.3.1"
      assert result["examples"]["phoenix"] =~ ".input"
    end

    test "explains H32 (submit buttons)" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "H32"}, [])

      assert result["issue"] == "H32"
      assert result["title"] == "Forms must have submit buttons"
      assert result["examples"]["good"] =~ "submit"
    end

    test "explains H57 (language)" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "H57"}, [])

      assert result["issue"] == "H57"
      assert result["title"] == "HTML element must have lang attribute"
      assert result["examples"]["good"] =~ "lang="
    end

    test "explains F65 (iframe title)" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "F65"}, [])

      assert result["issue"] == "F65"
      assert result["title"] == "Iframes must have title attributes"
    end

    test "explains contrast issues" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "CONTRAST"}, [])

      assert result["title"] == "Text must have sufficient color contrast"
      assert result["wcag"] =~ "1.4.3"
    end

    test "extracts code from full WCAG path" do
      {:ok, result} =
        ExplainIssue.execute(
          %{"issue" => "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37"},
          []
        )

      assert result["issue"] == "H37"
      assert result["title"] == "Images must have alt attributes"
    end
  end

  describe "execute/2 with analyzer findings" do
    test "explains memory_leak" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "memory_leak"}, [])

      assert result["issue"] == "memory_leak"
      assert result["title"] == "Memory leak detected in LiveView"
      assert is_binary(result["why"])
      assert length(result["phoenix_patterns"]) > 0
      assert result["examples"]["good"] =~ "stream"
    end

    test "explains n_plus_one" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "n_plus_one"}, [])

      assert result["issue"] == "n_plus_one"
      assert result["title"] == "N+1 query pattern detected"
      assert result["examples"]["good"] =~ "preload"
    end

    test "explains event_cascade" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "event_cascade"}, [])

      assert result["issue"] == "event_cascade"
      assert result["title"] == "Event cascade detected"
    end

    test "explains render_efficiency" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "render_efficiency"}, [])

      assert result["issue"] == "render_efficiency"
      assert result["title"] == "Wasted renders detected"
    end
  end

  describe "execute/2 with unknown issues" do
    test "returns generic response for unknown issue" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "UNKNOWN_CODE"}, [])

      assert result["issue"] == "UNKNOWN_CODE"
      assert result["title"] == "Unknown issue"
      assert result["phoenix_patterns"] == []
      assert "https://www.w3.org/WAI/WCAG21/quickref/" in result["resources"]
    end
  end

  describe "execute/2 with missing argument" do
    test "returns error when issue is missing" do
      {:error, message} = ExplainIssue.execute(%{}, [])

      assert message =~ "Missing required argument"
    end
  end

  describe "execute/2 case insensitivity" do
    test "handles lowercase codes" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "h37"}, [])

      assert result["issue"] == "H37"
    end

    test "handles mixed case codes" do
      {:ok, result} = ExplainIssue.execute(%{"issue" => "Memory_Leak"}, [])

      assert result["issue"] == "memory_leak"
    end
  end
end
