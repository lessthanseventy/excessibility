defmodule Excessibility.MCP.Tools.CheckRouteTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.CheckRoute

  describe "name/0" do
    test "returns tool name" do
      assert CheckRoute.name() == "check_route"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema with required url" do
      schema = CheckRoute.input_schema()

      assert schema["type"] == "object"
      assert schema["required"] == ["url"]
      assert Map.has_key?(schema["properties"], "url")
      assert Map.has_key?(schema["properties"], "port")
      assert Map.has_key?(schema["properties"], "wait_for")
      assert Map.has_key?(schema["properties"], "timeout")
    end
  end

  describe "execute/2 with missing url" do
    test "returns error when url is missing" do
      {:error, message} = CheckRoute.execute(%{}, [])

      assert message =~ "Missing required argument"
    end
  end

  describe "execute/2 when app not running" do
    test "returns error when Phoenix app not running" do
      # Use a port that's very unlikely to be in use
      {:error, message} = CheckRoute.execute(%{"url" => "/", "port" => 59_999}, [])

      assert message =~ "not running"
      assert message =~ "mix phx.server"
    end
  end

  describe "URL normalization" do
    # We can test URL normalization indirectly through the error message
    test "handles path-only URLs" do
      {:error, message} = CheckRoute.execute(%{"url" => "/users", "port" => 59_999}, [])

      # The error should mention the port, confirming URL was normalized
      assert message =~ "59999"
    end

    test "handles full URLs" do
      {:error, message} =
        CheckRoute.execute(%{"url" => "http://localhost:59999/users"}, [])

      assert message =~ "not running"
    end
  end
end
