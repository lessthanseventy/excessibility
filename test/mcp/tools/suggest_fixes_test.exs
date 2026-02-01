defmodule Excessibility.MCP.Tools.SuggestFixesTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.SuggestFixes

  describe "name/0" do
    test "returns tool name" do
      assert SuggestFixes.name() == "suggest_fixes"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema" do
      schema = SuggestFixes.input_schema()

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "pa11y_output")
      assert Map.has_key?(schema["properties"], "run_pa11y")
    end
  end

  describe "execute/2 with JSON input" do
    test "parses JSON issue array" do
      pa11y_output =
        Jason.encode!([
          %{
            "code" => "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37",
            "message" => "Img element missing an alt attribute",
            "selector" => "img.avatar",
            "context" => "<img src=\"avatar.png\" class=\"avatar\">"
          }
        ])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      assert result["status"] == "success"
      assert result["issues_found"] == 1

      [suggestion] = result["suggestions"]
      assert suggestion["issue"]["code"] == "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37"
      assert suggestion["suggestion"]["rule"] == "H37"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "alt"
    end

    test "parses JSON with issues key" do
      pa11y_output =
        Jason.encode!(%{
          "issues" => [
            %{
              "code" => "H44",
              "message" => "Form input missing label"
            }
          ]
        })

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      assert result["issues_found"] == 1
      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["rule"] == "H44"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "label"
    end
  end

  describe "execute/2 with text input" do
    test "parses text output with Error:" do
      pa11y_output = """
      Error: WCAG2AA.Principle1.Guideline1_1.1_1_1.H37 - Img element missing an alt attribute
      Warning: WCAG2AA.Principle1.Guideline1_3.1_3_1.H44 - Form input missing label
      """

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      assert result["status"] == "success"
      assert result["issues_found"] == 2
    end
  end

  describe "execute/2 fix suggestions" do
    test "suggests fix for H37 (alt text)" do
      pa11y_output = Jason.encode!([%{"code" => "H37", "message" => "Missing alt"}])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["rule"] == "H37"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "alt="
      assert suggestion["suggestion"]["wcag"] =~ "1.1.1"
    end

    test "suggests fix for H44 (form labels)" do
      pa11y_output = Jason.encode!([%{"code" => "H44", "message" => "Missing label"}])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["rule"] == "H44"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "<label"
      assert suggestion["suggestion"]["phoenix_fix"] =~ ".input"
    end

    test "suggests fix for H32 (submit buttons)" do
      pa11y_output = Jason.encode!([%{"code" => "H32", "message" => "No submit button"}])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["rule"] == "H32"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "phx-submit"
    end

    test "suggests fix for H57 (language attribute)" do
      pa11y_output = Jason.encode!([%{"code" => "H57", "message" => "Missing lang"}])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["rule"] == "H57"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "lang="
    end

    test "suggests fix for F65 (iframe titles)" do
      pa11y_output = Jason.encode!([%{"code" => "F65", "message" => "iframe without title"}])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["rule"] == "F65"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "title="
    end

    test "suggests fix for contrast issues" do
      pa11y_output =
        Jason.encode!([%{"code" => "contrast", "message" => "Color contrast is insufficient"}])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["rule"] == "Color Contrast"
      assert suggestion["suggestion"]["phoenix_fix"] =~ "4.5:1"
    end

    test "provides generic suggestion for unknown codes" do
      pa11y_output = Jason.encode!([%{"code" => "UNKNOWN", "message" => "Some issue"}])

      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => pa11y_output}, [])

      [suggestion] = result["suggestions"]
      assert suggestion["suggestion"]["phoenix_fix"] =~ "WCAG guidelines"
    end
  end

  describe "execute/2 with empty input" do
    test "handles empty string" do
      {:ok, result} = SuggestFixes.execute(%{"pa11y_output" => ""}, [])

      assert result["status"] == "success"
      assert result["issues_found"] == 0
      assert result["suggestions"] == []
    end

    test "handles missing pa11y_output" do
      {:ok, result} = SuggestFixes.execute(%{}, [])

      assert result["status"] == "success"
      assert result["issues_found"] == 0
    end
  end
end
