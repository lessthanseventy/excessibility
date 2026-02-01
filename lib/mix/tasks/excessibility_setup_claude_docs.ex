defmodule Mix.Tasks.Excessibility.SetupClaudeDocs do
  @shortdoc "Create .claude_docs/excessibility.md"

  @moduledoc """
  Create or update .claude_docs/excessibility.md

  ## Usage

      mix excessibility.setup_claude_docs

  ## Description

  Creates `.claude_docs/excessibility.md` with documentation teaching Claude
  how to use Excessibility for debugging Phoenix apps.

  If the file already exists, prompts before overwriting.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    claude_docs_dir = ".claude_docs"
    claude_docs_path = Path.join(claude_docs_dir, "excessibility.md")

    cond do
      File.exists?(claude_docs_path) ->
        if Mix.shell().yes?("#{claude_docs_path} already exists. Overwrite?") do
          write_docs(claude_docs_path)
          Mix.shell().info("✅ Updated #{claude_docs_path}")
        else
          Mix.shell().info("Skipped.")
        end

      File.exists?(claude_docs_dir) ->
        write_docs(claude_docs_path)
        Mix.shell().info("✅ Created #{claude_docs_path}")

      true ->
        File.mkdir_p!(claude_docs_dir)
        write_docs(claude_docs_path)
        Mix.shell().info("✅ Created #{claude_docs_dir}/")
        Mix.shell().info("✅ Created #{claude_docs_path}")
    end
  end

  defp write_docs(path) do
    File.write!(path, claude_docs_content())
  end

  defp claude_docs_content do
    """
    # Excessibility - Debugging Phoenix LiveView Tests

    **Zero-code-change LiveView debugging for AI assistants.**

    Excessibility automatically captures LiveView state during tests using telemetry,
    giving you complete execution context without modifying test code.

    ## When to Use Excessibility Skills

    **The excessibility plugin provides specialized skills - use them proactively:**

    - **Implementing LiveView features** (forms, modals, dynamic content)
      → Use `/e11y-tdd` skill for test-driven development with accessibility checking

    - **Debugging LiveView test failures or state issues**
      → Use `/e11y-debug` skill for timeline analysis and state inspection

    - **Fixing Pa11y or WCAG accessibility violations**
      → Use `/e11y-fix` skill for Phoenix-specific accessibility patterns

    **When these patterns match, using the skill is not optional** - it provides the workflow and tools to see actual rendered HTML and LiveView state, not just guesses.

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
    - **All render cycles** (form updates, state changes triggered by `render_change`, `render_click`, `render_submit`)
    - Real LiveView assigns at each step
    - Complete state timeline with memory tracking and performance metrics

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
    - `[:phoenix, :live_view, :render, :stop]` - **Captures all render cycles** (form updates, state changes)

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

    LLMs can't:
    - Run your Phoenix app
    - Attach debuggers
    - Use IEx.pry()
    - See what actually renders

    Snapshots give me the actual DOM output so I can reason about real
    behavior instead of guessing from documentation.

    ## Tips

    - Use descriptive test names - they become snapshot filenames
    - `mix excessibility.debug` automatically generates timeline.json
    - The timeline.json shows state changes clearly
    - Metadata in snapshots shows LiveView assigns at each step

    ## MCP Tools (if enabled)

    If you have the Excessibility MCP server configured, use these tools for faster iteration:

    ### Recommended Workflow for "find a11y/perf issues" requests

    **Do this in order - start fast, go deeper if needed:**

    1. **Start fast** - use `check_route` on key pages (instant results)
    2. **If issues found** - use `explain_issue` and `suggest_fixes` for guidance
    3. **For perf analysis** - run `e11y_debug` on a SINGLE test file (not directories!)

    ### Available MCP Tools

    - `check_route(url, port)` ⚡ **FAST** - Check running app for a11y issues. Use this first!
    - `e11y_check(test_args)` - Run Pa11y on snapshots
    - `e11y_debug(test_args, analyzers)` 🐢 **SLOW** - Run tests with telemetry capture
    - `explain_issue(issue)` - Explain WCAG codes with Phoenix examples
    - `suggest_fixes(run_pa11y)` - Get Phoenix-specific fix suggestions
    - `get_timeline()` - Read captured timeline data
    - `analyze_timeline(analyzers)` - Run analyzers on existing timeline
    - `list_analyzers()` - List available analyzers

    ### Important: Timeouts for Slow Tools

    `e11y_debug` and `e11y_check` run actual tests which can be slow (especially Wallaby browser tests).

    **Always:**
    - Specify a single test FILE, never a directory like `test/live/`
    - Pass `timeout: 300000` (5 minutes) to prevent hanging:

    ```
    e11y_debug(test_args: "test/my_test.exs", timeout: 300000)
    e11y_check(test_args: "test/my_test.exs", timeout: 300000)
    ```

    ### Quick Examples

    ```
    # Fast - check running app directly
    check_route(url: "/")
    check_route(url: "/signin")

    # Slow - always use single files + timeout
    e11y_debug(test_args: "test/my_app_web/live/page_live_test.exs", timeout: 300000)
    ```
    """
  end
end
