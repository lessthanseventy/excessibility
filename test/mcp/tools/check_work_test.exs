defmodule Excessibility.MCP.Tools.CheckWorkTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.CheckWork

  describe "name/0" do
    test "returns tool name" do
      assert CheckWork.name() == "check_work"
    end
  end

  describe "description/0" do
    test "returns a description" do
      assert is_binary(CheckWork.description())
      assert CheckWork.description() =~ "test"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema with required test_file and optional include_perf" do
      schema = CheckWork.input_schema()

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "test_file")
      assert schema["properties"]["test_file"]["type"] == "string"
      assert Map.has_key?(schema["properties"], "include_perf")
      assert schema["properties"]["include_perf"]["type"] == "boolean"
      assert schema["required"] == ["test_file"]
    end
  end

  describe "classify_violations/1" do
    test "returns :clean when no violations" do
      assert CheckWork.classify_violations([]) == :clean
    end

    test "returns :minor when only minor/moderate violations" do
      violations = [
        %{"id" => "color-contrast", "impact" => "minor"},
        %{"id" => "some-rule", "impact" => "moderate"}
      ]

      assert CheckWork.classify_violations(violations) == :minor
    end

    test "returns :critical when critical violations present" do
      violations = [
        %{"id" => "aria-label", "impact" => "critical"},
        %{"id" => "color-contrast", "impact" => "minor"}
      ]

      assert CheckWork.classify_violations(violations) == :critical
    end

    test "returns :critical when serious violations present" do
      violations = [
        %{"id" => "image-alt", "impact" => "serious"}
      ]

      assert CheckWork.classify_violations(violations) == :critical
    end
  end

  describe "build_summary/2" do
    test "builds summary with clean a11y and no perf" do
      a11y_result = %{"status" => "success", "output" => "No violations found"}
      summary = CheckWork.build_summary(a11y_result, nil)

      assert is_binary(summary)
      assert summary =~ "Accessibility"
    end

    test "builds summary with a11y violations and no perf" do
      a11y_result = %{
        "status" => "success",
        "output" => "Found 3 violations:\n- aria-label\n- image-alt\n- color-contrast"
      }

      summary = CheckWork.build_summary(a11y_result, nil)

      assert is_binary(summary)
      assert summary =~ "Accessibility"
      refute summary =~ "Performance"
    end

    test "builds summary with a11y result and perf result" do
      a11y_result = %{"status" => "success", "output" => "No violations found"}

      perf_result = %{
        "status" => "success",
        "output" => "Memory: stable\nPerformance: good"
      }

      summary = CheckWork.build_summary(a11y_result, perf_result)

      assert is_binary(summary)
      assert summary =~ "Accessibility"
      assert summary =~ "Performance"
    end

    test "builds summary with error a11y result" do
      a11y_result = %{"status" => "error", "output" => "Pa11y failed", "exit_code" => 1}
      summary = CheckWork.build_summary(a11y_result, nil)

      assert is_binary(summary)
      assert summary =~ "error" or summary =~ "Error" or summary =~ "failed"
    end

    test "builds summary with error perf result" do
      a11y_result = %{"status" => "success", "output" => "Clean"}

      perf_result = %{
        "status" => "error",
        "output" => "Debug failed",
        "exit_code" => 1
      }

      summary = CheckWork.build_summary(a11y_result, perf_result)

      assert summary =~ "Performance"
    end
  end
end
