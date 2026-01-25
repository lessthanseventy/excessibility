defmodule Mix.Tasks.Excessibility.SetupClaudeDocs do
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

  @shortdoc "Create .claude_docs/excessibility.md"

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

    LLMs can't:
    - Run your Phoenix app
    - Attach debuggers
    - Use IEx.pry()
    - See what actually renders

    Snapshots give me the actual DOM output so I can reason about real
    behavior instead of guessing from documentation.

    ## Tips

    - Use descriptive test names - they become snapshot filenames
    - Enable `generate_timeline: true` for complex flows
    - The timeline.json shows state changes clearly
    - Metadata in snapshots shows LiveView assigns at each step
    """
  end
end
