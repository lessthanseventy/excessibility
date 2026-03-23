defmodule Excessibility.MCP.Tools.DebugTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.Debug

  describe "name/0" do
    test "returns tool name" do
      assert Debug.name() == "debug"
    end
  end

  describe "description/0" do
    test "returns a description" do
      assert is_binary(Debug.description())
      assert Debug.description() =~ "debug"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema with required test_args" do
      schema = Debug.input_schema()

      assert schema["type"] == "object"
      assert schema["required"] == ["test_args"]
      assert Map.has_key?(schema["properties"], "test_args")
      assert Map.has_key?(schema["properties"], "analyzers")
      assert Map.has_key?(schema["properties"], "format")

      assert schema["properties"]["format"]["enum"] == ["markdown", "json"]
    end
  end

  describe "execute/2 with missing test_args" do
    test "returns error when test_args is missing" do
      {:error, message} = Debug.execute(%{}, [])

      assert message =~ "Missing required argument"
    end

    test "returns error when test_args is empty string" do
      {:error, message} = Debug.execute(%{"test_args" => ""}, [])

      assert message =~ "Missing required argument"
    end
  end

  describe "execute/2 with test_args" do
    test "runs mix excessibility.debug with test args" do
      result = Debug.execute(%{"test_args" => "test/my_test.exs:42"}, [])

      # Should return an ok tuple (even with error status) since subprocess handles failures
      assert {:ok, %{"output" => _output}} = result
    end

    test "runs with analyzers option" do
      result =
        Debug.execute(
          %{"test_args" => "test/my_test.exs", "analyzers" => "memory,performance"},
          []
        )

      assert {:ok, %{"output" => _output}} = result
    end

    test "runs with format option" do
      result =
        Debug.execute(
          %{"test_args" => "test/my_test.exs", "format" => "json"},
          []
        )

      assert {:ok, %{"output" => _output}} = result
    end

    test "runs with all options" do
      result =
        Debug.execute(
          %{
            "test_args" => "test/my_test.exs:42",
            "analyzers" => "memory,hypothesis",
            "format" => "markdown"
          },
          []
        )

      assert {:ok, %{"output" => _output}} = result
    end
  end
end
