defmodule Excessibility.MCP.Tools.GenerateTestTest do
  use ExUnit.Case, async: true

  alias Excessibility.MCP.Tools.GenerateTest

  describe "name/0" do
    test "returns tool name" do
      assert GenerateTest.name() == "generate_test"
    end
  end

  describe "input_schema/0" do
    test "returns valid schema with required route" do
      schema = GenerateTest.input_schema()

      assert schema["type"] == "object"
      assert schema["required"] == ["route"]
      assert Map.has_key?(schema["properties"], "route")
      assert Map.has_key?(schema["properties"], "module")
      assert Map.has_key?(schema["properties"], "test_type")
      assert Map.has_key?(schema["properties"], "app_module")

      assert schema["properties"]["test_type"]["enum"] == ["live_view", "controller"]
    end
  end

  describe "execute/2 with missing route" do
    test "returns error when route is missing" do
      {:error, message} = GenerateTest.execute(%{}, [])

      assert message =~ "Missing required argument"
    end
  end

  describe "execute/2 generates LiveView test" do
    test "generates basic LiveView test for simple route" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/users", "app_module" => "MyAppWeb"},
          []
        )

      assert result["route"] == "/users"
      assert result["test_type"] == "live_view"
      assert result["module"] =~ "UsersLiveTest"

      code = result["code"]
      assert code =~ "defmodule MyAppWeb.UsersLiveTest do"
      assert code =~ "use MyAppWeb.ConnCase"
      assert code =~ "use Excessibility"
      assert code =~ "import Phoenix.LiveViewTest"
      assert code =~ "live(conn, \"/users\")"
      assert code =~ "html_snapshot(view)"
    end

    test "generates test with auto-generated module name" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/posts/:id/comments", "app_module" => "BlogWeb"},
          []
        )

      # Should skip :id and join PostsComments
      assert result["module"] == "BlogWeb.PostsCommentsLiveTest"
    end

    test "generates test with custom module name" do
      {:ok, result} =
        GenerateTest.execute(
          %{
            "route" => "/dashboard",
            "module" => "MyAppWeb.AdminDashboardTest",
            "app_module" => "MyAppWeb"
          },
          []
        )

      assert result["module"] == "MyAppWeb.AdminDashboardTest"
      assert result["code"] =~ "defmodule MyAppWeb.AdminDashboardTest do"
    end

    test "suggests appropriate file path" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/users", "app_module" => "MyAppWeb"},
          []
        )

      assert result["suggested_path"] =~ "test/"
      assert result["suggested_path"] =~ ".exs"
      assert result["suggested_path"] =~ "live"
    end
  end

  describe "execute/2 generates controller test" do
    test "generates controller test when test_type is controller" do
      {:ok, result} =
        GenerateTest.execute(
          %{
            "route" => "/api/health",
            "test_type" => "controller",
            "app_module" => "MyAppWeb"
          },
          []
        )

      assert result["test_type"] == "controller"

      code = result["code"]
      assert code =~ "use MyAppWeb.ConnCase"
      assert code =~ "use Excessibility"
      assert code =~ "get(conn, \"/api/health\")"
      assert code =~ "html_snapshot(conn)"
      assert code =~ "html_response(conn, 200)"
      refute code =~ "import Phoenix.LiveViewTest"
    end
  end

  describe "execute/2 generates interaction tests" do
    test "generates form test for new routes" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/users/new", "app_module" => "MyAppWeb"},
          []
        )

      code = result["code"]
      assert code =~ "form submission is accessible"
      assert code =~ ~s|form("#form-id"|
      assert code =~ "render_submit"
    end

    test "generates data test for routes with :id" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/users/:id", "app_module" => "MyAppWeb"},
          []
        )

      code = result["code"]
      assert code =~ "page with data is accessible"
      assert code =~ "Create test data"
    end

    test "generates interactive test for other routes" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/dashboard", "app_module" => "MyAppWeb"},
          []
        )

      code = result["code"]
      assert code =~ "interactive elements are accessible"
    end
  end

  describe "execute/2 handles edge cases" do
    test "handles root route" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/", "app_module" => "MyAppWeb"},
          []
        )

      assert result["module"] =~ "HomeLiveTest"
    end

    test "handles deeply nested routes" do
      {:ok, result} =
        GenerateTest.execute(
          %{"route" => "/admin/settings/notifications", "app_module" => "MyAppWeb"},
          []
        )

      assert result["module"] == "MyAppWeb.AdminSettingsNotificationsLiveTest"
    end
  end
end
