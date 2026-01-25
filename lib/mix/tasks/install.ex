defmodule Mix.Tasks.Excessibility.Install do
  @shortdoc "Installs Excessibility configuration into your project"
  @moduledoc """
  Installs Excessibility into a host project using Igniter.

  This task can be invoked directly or via `mix igniter.install excessibility`. It adds the
  recommended configuration to the target project's `config/test.exs` and (by default) runs
  `npm install` inside the vendored Excessibility assets directory to fetch Pa11y.

  Requires Igniter to be installed in the host project.
  """
  use Igniter.Mix.Task

  alias Igniter.Mix.Task.Info
  alias Igniter.Project.Config
  alias Igniter.Project.Module, as: ProjectModule

  @impl true
  def info(_argv, _source) do
    %Info{
      group: :excessibility,
      schema: [
        endpoint: :string,
        head_render_path: :string,
        assets_dir: :string,
        skip_npm: :boolean
      ],
      defaults: [skip_npm: false, head_render_path: "/"],
      example: "mix excessibility.install --endpoint MyAppWeb.Endpoint --head-render-path /login"
    }
  end

  @impl true
  def igniter(igniter) do
    opts = igniter.args.options

    endpoint = fallback_endpoint(opts[:endpoint], igniter)
    head_render_path = opts[:head_render_path] || "/"
    assets_dir = opts[:assets_dir] || default_assets_dir()
    skip_npm? = opts[:skip_npm]

    igniter
    |> ensure_test_config(endpoint, head_render_path)
    |> ensure_test_helper()
    |> ensure_pa11y_config()
    |> maybe_install_pa11y(assets_dir, skip_npm?)
    |> maybe_create_claude_docs()
  end

  defp fallback_endpoint(nil, igniter) do
    igniter
    |> Igniter.Libs.Phoenix.web_module()
    |> Module.concat("Endpoint")
  rescue
    _ -> "MyAppWeb.Endpoint"
  end

  defp fallback_endpoint(endpoint, _igniter) when is_binary(endpoint), do: ProjectModule.parse(endpoint)

  defp fallback_endpoint(module, _igniter), do: module

  defp ensure_test_config(igniter, endpoint, head_render_path) do
    igniter
    |> Config.configure("test.exs", :excessibility, [:endpoint], endpoint)
    |> Config.configure("test.exs", :excessibility, [:head_render_path], head_render_path)
    |> Config.configure("test.exs", :excessibility, [:browser_mod], Wallaby.Browser)
    |> Config.configure("test.exs", :excessibility, [:live_view_mod], Excessibility.LiveView)
    |> Config.configure("test.exs", :excessibility, [:system_mod], Excessibility.System)
  end

  defp ensure_test_helper(igniter) do
    test_helper_path = "test/test_helper.exs"

    telemetry_code = """
    # Enable Excessibility telemetry-based auto-capture for debugging
    # This is automatically enabled when running: mix excessibility.debug
    if System.get_env("EXCESSIBILITY_TELEMETRY_CAPTURE") == "true" do
      Excessibility.TelemetryCapture.attach()
    end
    """

    Igniter.update_file(igniter, test_helper_path, fn source ->
      content = Rewrite.Source.get(source, :content)

      # Check if already present to avoid duplicates
      if String.contains?(content, "Excessibility.TelemetryCapture.attach") do
        source
      else
        # Append before ExUnit.start() if present, otherwise at end
        updated_content =
          if String.contains?(content, "ExUnit.start()") do
            String.replace(content, "ExUnit.start()", telemetry_code <> "\nExUnit.start()")
          else
            content <> "\n\n" <> telemetry_code
          end

        Rewrite.Source.update(source, :content, updated_content)
      end
    end)
  end

  defp ensure_pa11y_config(igniter) do
    Igniter.create_or_update_file(igniter, "pa11y.json", pa11y_config(), fn source ->
      # Don't overwrite existing config
      source
    end)
  end

  defp pa11y_config do
    """
    {
      "ignore": [
        "WCAG2AA.Principle3.Guideline3_2.3_2_2.H32.2"
      ]
    }
    """
  end

  defp maybe_install_pa11y(igniter, assets_dir, true), do: add_npm_notice(igniter, assets_dir)

  defp maybe_install_pa11y(igniter, assets_dir, _skip?) do
    package_json = Path.join(assets_dir, "package.json")

    cond do
      igniter.args.options[:dry_run] ->
        add_npm_notice(igniter, assets_dir)

      not File.exists?(package_json) ->
        Igniter.add_warning(
          igniter,
          "Could not find package.json inside #{assets_dir}. Skipping npm install."
        )

      true ->
        Mix.shell().info("Installing npm packages in #{assets_dir}...")

        case System.cmd("npm", ["install"], cd: assets_dir, into: IO.stream(:stdio, :line)) do
          {_, 0} ->
            Mix.shell().info("✔ Pa11y installed under #{assets_dir}")
            igniter

          {_, status} ->
            Igniter.add_warning(
              igniter,
              "npm install exited with status #{status}. Run it manually in #{assets_dir}."
            )
        end
    end
  end

  defp add_npm_notice(igniter, assets_dir) do
    Igniter.add_notice(
      igniter,
      "Run `npm install` inside #{assets_dir} to install Pa11y dependencies."
    )
  end

  defp default_assets_dir do
    dep_path = Mix.Project.deps_paths()[:excessibility] || File.cwd!()
    Path.join(dep_path, "assets")
  end

  defp maybe_create_claude_docs(igniter) do
    claude_docs_path = ".claude_docs/excessibility.md"

    if File.exists?(claude_docs_path) do
      # Ask if they want to update
      Igniter.add_notice(
        igniter,
        """
        Found existing #{claude_docs_path}

        To update with latest Excessibility features, run:
        mix excessibility.setup_claude_docs
        """
      )
    else
      if File.exists?(".claude_docs") do
        # .claude_docs exists, create the file
        Igniter.create_or_update_file(igniter, claude_docs_path, claude_docs_content(), fn source ->
          # File exists, don't overwrite
          source
        end)
      else
        # Suggest creating .claude_docs
        Igniter.add_notice(
          igniter,
          """
          💡 Using Excessibility with Claude?

          Create .claude_docs/excessibility.md to teach Claude how to:
          - Use mix excessibility.debug for instant context
          - Automatically capture LiveView state changes
          - Analyze snapshots without manual file management

          Run: mix excessibility.setup_claude_docs
          """
        )
      end
    end
  end

  defp claude_docs_content do
    """
    # Excessibility - Debugging Phoenix LiveView Tests

    **Zero-code-change LiveView debugging for AI assistants.**

    Excessibility automatically captures LiveView state during tests using telemetry,
    giving you complete execution context without modifying test code.

    ## Key Feature: Telemetry-Based Auto-Capture

    Debug **any existing LiveView test** with automatic snapshot capture:

    ```elixir
    # Your test - completely vanilla, zero Excessibility code
    test "user interaction flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#button") |> render_click()
      view |> element("#form") |> render_submit(%{name: "Alice"})
      assert render(view) =~ "Welcome Alice"
    end
    ```

    Debug it:
    ```bash
    mix excessibility.debug test/my_test.exs
    ```

    **Automatically captures:**
    - LiveView mount events
    - All handle_event calls (clicks, submits, etc.)
    - Real LiveView assigns at each step
    - Complete state timeline

    ## What Gets Captured

    Example telemetry snapshot:
    ```html
    <!--
    Excessibility Telemetry Snapshot
    Test: test user interaction flow
    Sequence: 2
    Event: handle_event:submit_form
    Timestamp: 2026-01-25T10:30:12.345Z
    View Module: MyAppWeb.DashboardLive
    Assigns: %{
      current_user: %User{name: "Alice"},
      form_data: %{name: "Alice"},
      submitted: true
    }
    -->
    ```

    Each snapshot includes:
    - Real LiveView assigns (state at that moment)
    - Event sequence and type
    - Timestamp
    - View module

    ## Quick Commands

    ### Debug a failing test
    ```bash
    mix excessibility.debug test/my_test.exs
    ```
    Generates markdown report with:
    - Test results and errors
    - All captured snapshots with inline HTML
    - Event timeline showing state changes
    - Real LiveView assigns at each snapshot

    ### Show latest debug report
    ```bash
    mix excessibility.latest
    ```
    Re-displays most recent debug without re-running test.

    ### Create shareable package
    ```bash
    mix excessibility.package test/my_test.exs
    ```
    Creates directory with MANIFEST, timeline.json, and all snapshots.

    ## How It Works

    Excessibility hooks into Phoenix LiveView's built-in telemetry events:
    - `[:phoenix, :live_view, :mount, :stop]`
    - `[:phoenix, :live_view, :handle_event, :stop]`
    - `[:phoenix, :live_view, :handle_params, :stop]`

    When you run `mix excessibility.debug`:
    1. Sets environment variable to enable telemetry capture
    2. Attaches telemetry handlers
    3. Runs your test (unchanged)
    4. Captures snapshots with real assigns from LiveView process
    5. Generates complete debug report

    **No test changes needed** - works with vanilla Phoenix LiveView tests!

    ## Typical Workflow

    1. User reports failing test
    2. Run: `mix excessibility.debug test/failing_test.exs`
    3. Read the generated `test/excessibility/latest_debug.md`
    4. Analyze snapshots showing LiveView state at each step
    5. Identify the issue from real execution context
    6. Suggest fixes based on actual state changes

    ## Why This Helps Claude

    Without snapshots, I'm guessing based on code. With Excessibility:
    - See actual LiveView assigns at each step
    - Track state changes through event sequence
    - Compare expected vs actual DOM output
    - Understand real execution flow, not theoretical

    ## Alternative: Manual Capture

    For fine-grained control, you can manually capture:
    ```elixir
    use Excessibility

    @tag capture_snapshots: true
    test "manual capture", %{conn: conn} do
      {:ok, view, _} = live(conn, "/")
      html_snapshot(view)  # Manual snapshot with metadata

      view |> element("#btn") |> render_click()
      html_snapshot(view)  # Another snapshot
    end
    ```

    ## Tips for Using This with Claude

    - Point me to `test/excessibility/latest_debug.md` after running debug command
    - The telemetry snapshots show real LiveView state, not just rendered HTML
    - Timeline shows event sequence - useful for complex interactions
    - Assigns help understand what changed between events
    """
  end
end
