defmodule Excessibility.MCP.Tools.ListViolationsTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.ListViolations

  describe "name/0" do
    test "returns tool name" do
      assert ListViolations.name() == "list_violations"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema" do
      schema = ListViolations.input_schema()

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "path")
      assert Map.has_key?(schema["properties"], "run_pa11y")
    end
  end

  describe "execute/2 with JSON array input" do
    test "parses JSON issue array" do
      pa11y_output =
        Jason.encode!([
          %{
            "code" => "WCAG2AA.Principle1.Guideline1_1.1_1_1.H37",
            "type" => "error",
            "message" => "Img element missing an alt attribute",
            "selector" => "img.avatar",
            "context" => "<img src=\"avatar.png\" class=\"avatar\">"
          },
          %{
            "code" => "WCAG2AA.Principle1.Guideline1_3.1_3_1.H44",
            "type" => "warning",
            "message" => "Form input missing label",
            "selector" => "input#email"
          }
        ])

      # Write temp file
      path = Path.join(System.tmp_dir!(), "pa11y_test_#{:rand.uniform(10_000)}.json")
      File.write!(path, pa11y_output)

      {:ok, result} = ListViolations.execute(%{"path" => path}, [])

      File.rm!(path)

      assert length(result["violations"]) == 2
      assert result["summary"]["total"] == 2
      assert result["summary"]["errors"] == 1
      assert result["summary"]["warnings"] == 1

      [v1, v2] = result["violations"]
      assert v1["rule"] == "H37"
      assert v1["fix_hint"] == "Add alt attribute to image"
      assert v2["rule"] == "H44"
    end
  end

  describe "execute/2 with issues key format" do
    test "parses JSON with issues key" do
      pa11y_output =
        Jason.encode!(%{
          "issues" => [
            %{
              "code" => "H37",
              "type" => "error",
              "message" => "Missing alt"
            }
          ]
        })

      path = Path.join(System.tmp_dir!(), "pa11y_test_#{:rand.uniform(10_000)}.json")
      File.write!(path, pa11y_output)

      {:ok, result} = ListViolations.execute(%{"path" => path}, [])

      File.rm!(path)

      assert result["summary"]["total"] == 1
      [violation] = result["violations"]
      assert violation["rule"] == "H37"
    end
  end

  describe "execute/2 with results format" do
    test "parses JSON with results key containing file map" do
      pa11y_output =
        Jason.encode!(%{
          "results" => %{
            "test_snapshot.html" => [
              %{
                "code" => "H57",
                "type" => "error",
                "message" => "Missing lang attribute"
              }
            ],
            "another_snapshot.html" => [
              %{
                "code" => "F65",
                "type" => "warning",
                "message" => "Iframe missing title"
              }
            ]
          }
        })

      path = Path.join(System.tmp_dir!(), "pa11y_test_#{:rand.uniform(10_000)}.json")
      File.write!(path, pa11y_output)

      {:ok, result} = ListViolations.execute(%{"path" => path}, [])

      File.rm!(path)

      assert result["summary"]["total"] == 2
      assert result["summary"]["by_rule"]["H57"] == 1
      assert result["summary"]["by_rule"]["F65"] == 1

      # Check that file names are preserved
      files = Enum.map(result["violations"], & &1["file"])
      assert "test_snapshot.html" in files
      assert "another_snapshot.html" in files
    end
  end

  describe "execute/2 summary statistics" do
    test "calculates summary by type and rule" do
      pa11y_output =
        Jason.encode!([
          %{"code" => "H37", "type" => "error", "message" => "Missing alt"},
          %{"code" => "H37", "type" => "error", "message" => "Missing alt"},
          %{"code" => "H44", "type" => "warning", "message" => "Missing label"},
          %{"code" => "contrast", "type" => "notice", "message" => "Low contrast"}
        ])

      path = Path.join(System.tmp_dir!(), "pa11y_test_#{:rand.uniform(10_000)}.json")
      File.write!(path, pa11y_output)

      {:ok, result} = ListViolations.execute(%{"path" => path}, [])

      File.rm!(path)

      assert result["summary"]["total"] == 4
      assert result["summary"]["errors"] == 2
      assert result["summary"]["warnings"] == 1
      assert result["summary"]["notices"] == 1
      assert result["summary"]["by_rule"]["H37"] == 2
      assert result["summary"]["by_rule"]["H44"] == 1
      assert result["summary"]["by_rule"]["contrast"] == 1
    end
  end

  describe "execute/2 with empty/missing input" do
    test "handles missing file path gracefully" do
      {:ok, result} = ListViolations.execute(%{}, [])

      assert result["violations"] == []
      assert result["summary"]["total"] == 0
    end

    test "handles nonexistent file" do
      {:ok, result} = ListViolations.execute(%{"path" => "/nonexistent/file.json"}, [])

      assert result["violations"] == []
      assert result["summary"]["total"] == 0
    end
  end

  describe "execute/2 fix hints" do
    test "provides fix hints for known rules" do
      violations = [
        %{"code" => "H37", "message" => "test"},
        %{"code" => "H44", "message" => "test"},
        %{"code" => "H32", "message" => "test"},
        %{"code" => "H57", "message" => "test"},
        %{"code" => "F65", "message" => "test"},
        %{"code" => "contrast", "message" => "test"},
        %{"code" => "UNKNOWN", "message" => "test"}
      ]

      pa11y_output = Jason.encode!(violations)
      path = Path.join(System.tmp_dir!(), "pa11y_test_#{:rand.uniform(10_000)}.json")
      File.write!(path, pa11y_output)

      {:ok, result} = ListViolations.execute(%{"path" => path}, [])

      File.rm!(path)

      hints = Enum.map(result["violations"], & &1["fix_hint"])

      assert "Add alt attribute to image" in hints
      assert "Add label element with for attribute matching input id" in hints
      assert "Add submit button to form (or use phx-submit)" in hints
      assert "Add lang attribute to html element" in hints
      assert "Add title attribute to iframe" in hints
      assert "Increase color contrast ratio (4.5:1 for text)" in hints
      assert nil in hints
    end
  end
end
