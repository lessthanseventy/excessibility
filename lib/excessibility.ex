defmodule Excessibility do
  @moduledoc """
  Accessibility snapshot testing for Phoenix applications.

  Excessibility captures HTML snapshots during tests and runs them through Pa11y
  for WCAG compliance checking.

  ## Usage

  Add `use Excessibility` to your test modules:

      defmodule MyAppWeb.PageControllerTest do
        use MyAppWeb.ConnCase
        use Excessibility

        test "home page is accessible", %{conn: conn} do
          conn = get(conn, "/")
          html_snapshot(conn)
          assert html_response(conn, 200)
        end
      end

  ## Supported Sources

  The `html_snapshot/2` macro works with:

  - `Plug.Conn` - Controller test responses
  - `Wallaby.Session` - Browser-based feature tests
  - `Phoenix.LiveViewTest.View` - LiveView test views
  - `Phoenix.LiveViewTest.Element` - LiveView elements

  ## Options

  - `:name` - Custom filename (default: auto-generated from module/line)
  - `:prompt_on_diff` - Interactive diff resolution (default: `true`)
  - `:tag_on_diff` - Save `.good.html` and `.bad.html` on diff (default: `true`)
  - `:screenshot?` - Generate PNG screenshots (default: `false`)
  - `:open_browser?` - Open snapshot in browser (default: `false`)
  - `:cleanup?` - Delete existing module snapshots first (default: `false`)

  See the [README](readme.html) for full documentation.
  """

  @doc """
  Sets up the module for snapshot testing by importing `Excessibility`.

  This makes the `html_snapshot/1` and `html_snapshot/2` macros available
  in your test module without needing to fully qualify them.

  ## Example

      use Excessibility

  ## Auto-Capture

  Use `@tag capture_snapshots: true` to automatically capture snapshots:

      @tag capture_snapshots: true
      test "user flow", %{conn: conn} do
        {:ok, view, _html} = live(conn, "/dashboard")
        # Snapshots captured automatically
      end
  """
  defmacro __using__(_opts) do
    quote do
      import Excessibility, only: [html_snapshot: 1, html_snapshot: 2]

      setup context do
        # Store test name for telemetry capture
        if System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true" do
          test_name = context[:test]
          Process.put(:excessibility_test_name, test_name)
          Excessibility.TelemetryCapture.clear_snapshots(test_name)
        end

        if context[:capture_snapshots] || context[:capture] do
          test_name = context[:test]
          Excessibility.Capture.init_capture(test_name, context)
        end

        on_exit(fn ->
          # Write telemetry snapshots to files if captured
          if System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true" do
            Excessibility.TelemetryCapture.write_snapshots(context[:test])
            Excessibility.TelemetryCapture.clear_snapshots()
          end

          # Save timeline if requested
          if context[:generate_timeline] do
            Excessibility.Capture.save_timeline()
          end

          Excessibility.Capture.clear_state()
        end)

        :ok
      end
    end
  end

  @doc """
  Captures an HTML snapshot from a test source for accessibility testing.

  Returns the source unchanged, allowing use in pipelines.

  ## Parameters

  - `source` - A `Plug.Conn`, `Wallaby.Session`, `Phoenix.LiveViewTest.View`,
    or `Phoenix.LiveViewTest.Element`
  - `opts` - Keyword list of options (see module docs)

  ## Examples

      # Basic snapshot
      html_snapshot(conn)

      # With options
      html_snapshot(conn,
        name: "login_form.html",
        screenshot?: true,
        prompt_on_diff: false
      )

      # In a pipeline
      conn
      |> get("/")
      |> html_snapshot()
      |> html_response(200)
  """
  defmacro html_snapshot(source, opts \\ []) do
    quote do
      Excessibility.Snapshot.html_snapshot(unquote(source), __ENV__, __MODULE__, unquote(opts))
    end
  end
end
