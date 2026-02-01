defmodule Excessibility.MCP.Tools.GenerateTest do
  @moduledoc """
  MCP tool for scaffolding accessibility snapshot tests.

  Generates test code for a route, which can be used as a starting point.
  Returns the generated code as a string - does not write files directly.
  """

  @behaviour Excessibility.MCP.Tool

  alias Excessibility.MCP.ClientContext

  @impl true
  def name, do: "generate_test"

  @impl true
  def description do
    "Generate accessibility snapshot test code for a route. " <>
      "Returns the test code as a string for you to save to a file."
  end

  @impl true
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "route" => %{
          "type" => "string",
          "description" => "The route to test (e.g., '/users', '/posts/:id')"
        },
        "module" => %{
          "type" => "string",
          "description" => "Test module name (e.g., 'MyAppWeb.UserLiveTest'). Auto-generated if not provided."
        },
        "test_type" => %{
          "type" => "string",
          "enum" => ["live_view", "controller"],
          "description" => "Type of test to generate (default: live_view)"
        },
        "app_module" => %{
          "type" => "string",
          "description" => "Application web module (e.g., 'MyAppWeb'). Auto-detected if not provided."
        }
      },
      "required" => ["route"]
    }
  end

  @impl true
  def execute(%{"route" => route} = args, opts) do
    progress_callback = Keyword.get(opts, :progress_callback)

    if progress_callback, do: progress_callback.("Generating test...", 0)

    test_type = Map.get(args, "test_type", "live_view")
    app_module = Map.get(args, "app_module") || detect_app_module()
    module_name = Map.get(args, "module") || generate_module_name(route, app_module)

    test_code = generate_test_code(route, module_name, app_module, test_type)
    file_path = suggest_file_path(module_name)

    if progress_callback, do: progress_callback.("Complete", 100)

    {:ok,
     %{
       "code" => test_code,
       "suggested_path" => file_path,
       "module" => module_name,
       "route" => route,
       "test_type" => test_type
     }}
  end

  def execute(_args, _opts) do
    {:error, "Missing required argument: route"}
  end

  defp detect_app_module do
    # Try to detect from client's mix.exs
    client_cwd = ClientContext.get_cwd()
    mix_path = Path.join(client_cwd, "mix.exs")

    if File.exists?(mix_path) do
      detect_from_mix_exs(mix_path)
    else
      "MyAppWeb"
    end
  end

  defp detect_from_mix_exs(mix_path) do
    case File.read(mix_path) do
      {:ok, content} ->
        # Look for patterns like: app: :live_beats or app: :my_app
        case Regex.run(~r/app:\s*:(\w+)/, content) do
          [_, app_name] ->
            # Convert :live_beats to LiveBeatsWeb
            app_name
            |> Macro.camelize()
            |> Kernel.<>("Web")

          nil ->
            "MyAppWeb"
        end

      {:error, _} ->
        "MyAppWeb"
    end
  end

  defp generate_module_name(route, app_module) do
    # Convert route to module name
    # / -> HomeLiveTest
    # /users -> UsersLiveTest
    # /users/:id -> UsersLiveTest
    # /posts/:id/comments -> PostsCommentsLiveTest
    base_name =
      route
      |> String.trim_leading("/")
      |> String.split("/")
      |> Enum.reject(&(String.starts_with?(&1, ":") or &1 == ""))
      |> Enum.map(&Macro.camelize/1)
      |> case do
        [] -> "Home"
        parts -> Enum.join(parts)
      end

    "#{app_module}.#{base_name}LiveTest"
  end

  defp suggest_file_path(module_name) do
    # MyAppWeb.UsersLiveTest -> test/my_app_web/live/users_live_test.exs
    parts = String.split(module_name, ".")

    filename =
      parts
      |> List.last()
      |> Macro.underscore()
      |> Kernel.<>(".exs")

    base_path = parts |> Enum.drop(-1) |> Enum.map(&Macro.underscore/1) |> Path.join()

    Path.join(["test", base_path, "live", filename])
  end

  defp generate_test_code(route, module_name, app_module, "live_view") do
    """
    defmodule #{module_name} do
      use #{app_module}.ConnCase
      use Excessibility

      import Phoenix.LiveViewTest

      describe "#{route}" do
        test "page is accessible", %{conn: conn} do
          {:ok, view, _html} = live(conn, "#{route}")

          # Capture snapshot for Pa11y accessibility check
          html_snapshot(view)

          # Add your functional assertions here
          # assert has_element?(view, "h1")
        end

        #{generate_interaction_test(route)}
      end
    end
    """
  end

  defp generate_test_code(route, module_name, app_module, "controller") do
    """
    defmodule #{module_name} do
      use #{app_module}.ConnCase
      use Excessibility

      describe "#{route}" do
        test "page is accessible", %{conn: conn} do
          conn = get(conn, "#{route}")

          # Capture snapshot for Pa11y accessibility check
          html_snapshot(conn)

          # Add your functional assertions here
          assert html_response(conn, 200)
        end
      end
    end
    """
  end

  defp generate_interaction_test(route) do
    cond do
      String.contains?(route, "new") or String.contains?(route, "edit") ->
        """
        test "form submission is accessible", %{conn: conn} do
              {:ok, view, _html} = live(conn, "#{route}")

              # Snapshot before form submission
              html_snapshot(view)

              # Fill form and submit
              view
              |> form("#form-id", %{field: "value"})
              |> render_submit()

              # Snapshot after submission (captures error states)
              html_snapshot(view)
            end
        """

      String.contains?(route, ":id") ->
        """
        test "page with data is accessible", %{conn: conn} do
              # Create test data
              # item = insert(:item)

              {:ok, view, _html} = live(conn, "#{route}")
              html_snapshot(view)

              # Test any interactive elements
              # view |> element("button") |> render_click()
              # html_snapshot(view)
            end
        """

      true ->
        """
        test "interactive elements are accessible", %{conn: conn} do
              {:ok, view, _html} = live(conn, "#{route}")

              # Test interactions
              # view |> element("button.action") |> render_click()
              # html_snapshot(view)
            end
        """
    end
  end
end
