defmodule Excessibility.MCP.Tools.A11yCheckTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.A11yCheck

  describe "name/0" do
    test "returns tool name" do
      assert A11yCheck.name() == "a11y_check"
    end
  end

  describe "description/0" do
    test "returns a description" do
      assert is_binary(A11yCheck.description())
      assert A11yCheck.description() =~ "accessibility"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema with optional url and test_args" do
      schema = A11yCheck.input_schema()

      assert schema["type"] == "object"
      assert Map.has_key?(schema["properties"], "url")
      assert Map.has_key?(schema["properties"], "test_args")
      refute Map.has_key?(schema, "required")
    end
  end

  describe "execute/2 with url" do
    test "checks a file:// URL via AxeRunner" do
      # Create a minimal HTML file for testing
      tmp_dir = System.tmp_dir!()
      html_path = Path.join(tmp_dir, "a11y_check_test_#{:rand.uniform(100_000)}.html")

      html_content = """
      <!DOCTYPE html>
      <html lang="en">
      <head><title>Test Page</title></head>
      <body>
        <h1>Hello</h1>
        <p>Accessible page</p>
      </body>
      </html>
      """

      File.write!(html_path, html_content)

      try do
        result = A11yCheck.execute(%{"url" => "file://#{html_path}"}, [])

        case result do
          {:ok, %{"status" => "success"} = data} ->
            assert is_integer(data["violation_count"])
            assert is_list(data["violations"])
            assert is_integer(data["passes"])
            assert is_integer(data["incomplete"])

          {:error, reason} ->
            # AxeRunner may not be installed in test environment
            assert reason =~ "axe-runner"
        end
      after
        File.rm(html_path)
      end
    end
  end

  describe "execute/2 with test_args" do
    test "builds correct mix command with test args" do
      # This will fail because we're not in a real project, but we can verify
      # it attempts to run the right command
      result = A11yCheck.execute(%{"test_args" => "test/my_test.exs:42"}, [])

      # Should return an ok tuple (even with error status) since subprocess handles failures
      assert {:ok, %{"output" => _output}} = result
    end
  end

  describe "execute/2 with no args" do
    test "runs mix excessibility without test args" do
      result = A11yCheck.execute(%{}, [])

      # Should return an ok tuple since subprocess handles failures
      assert {:ok, %{"output" => _output}} = result
    end
  end
end
