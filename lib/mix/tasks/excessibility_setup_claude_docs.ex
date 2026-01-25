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
    # Excessibility - LLM Development Workflow

    Excessibility helps debug Phoenix apps by capturing HTML snapshots during tests.

    ## Quick Commands

    ### Debug a test
    ```bash
    mix excessibility.debug test/my_test.exs
    ```
    Runs test, captures snapshots, outputs complete debug report with inline HTML.

    ### Show latest debug session
    ```bash
    mix excessibility.latest
    ```
    Re-displays most recent debug without re-running test.

    ### Create shareable package
    ```bash
    mix excessibility.package test/my_test.exs
    ```
    Creates directory with MANIFEST, timeline, and all snapshots.

    ## In Tests

    ### Auto-capture snapshots
    ```elixir
    @tag capture_snapshots: true
    test "user flow", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/dashboard")
      view |> element("#button") |> render_click()
      # Snapshots captured automatically at each step
    end
    ```

    ### Granular control
    ```elixir
    @tag capture: :clicks           # Only clicks
    @tag capture: [:initial, :final] # Just first and last
    @tag capture: :on_change        # Only when DOM changes
    ```

    ## Snapshot Metadata

    Every snapshot includes metadata as HTML comment:
    - Test name
    - Event sequence number
    - Event type (click, change, submit, etc.)
    - LiveView assigns at that moment
    - Timestamp
    - Previous/next snapshot references

    ## Typical Workflow

    1. User reports failing test
    2. You run: `mix excessibility.debug test/failing_test.exs`
    3. Paste the output here (or tell me to read latest_debug.md)
    4. I analyze snapshots and identify the issue
    5. I suggest fixes

    ## Why This Helps

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
