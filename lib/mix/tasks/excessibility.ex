defmodule Mix.Tasks.Excessibility do
  @shortdoc "Run accessibility checks on snapshots"

  @moduledoc """
  Runs axe-core accessibility checks on HTML snapshots.

  ## Usage

  With no arguments, checks ALL existing snapshots:

      mix excessibility

  With arguments, runs tests first then checks NEW snapshots only:

      # Run a test file
      mix excessibility test/my_app_web/live/page_live_test.exs

      # Run a specific test by line number
      mix excessibility test/my_app_web/live/page_live_test.exs:42

      # Run tests with a tag
      mix excessibility --only a11y

      # Run a describe block
      mix excessibility test/my_test.exs:10

  ## Configuration

  - `:axe_disable_rules` - List of axe rule IDs to disable (default: `[]`)
  - `:excessibility_output_path` - Base directory for snapshots (default: `"test/excessibility"`)

  ## Prerequisites

  Run `mix excessibility.install` first to install axe-core and Playwright via npm.
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run([]) do
    # No args - check all existing snapshots
    run_axe_on_all()
  end

  def run(args) do
    # With args - run tests first, then check new snapshots
    run_tests_then_check(args)
  end

  defp run_axe_on_all do
    files = list_snapshots()

    if Enum.empty?(files) do
      Mix.shell().info("""
      No snapshots found in #{snapshot_dir()}.

      Run your tests first to generate snapshots:

          mix test

      Or run a specific test:

          mix excessibility test/my_test.exs
      """)

      exit({:shutdown, 0})
    end

    Mix.shell().info("Checking #{length(files)} snapshot(s)...\n")
    run_axe(files)
  end

  defp run_tests_then_check(args) do
    # Get snapshot count before test
    snapshots_before = list_snapshots()

    # Run mix test with all args passed through
    Mix.shell().info("Running: mix test #{Enum.join(args, " ")}\n")
    {_output, exit_code} = System.cmd("mix", ["test" | args], into: IO.stream(:stdio, :line))

    if exit_code != 0 do
      Mix.shell().error("\nTests failed - skipping accessibility check")
      exit({:shutdown, exit_code})
    end

    # Get new snapshots
    snapshots_after = list_snapshots()
    new_snapshots = snapshots_after -- snapshots_before

    if Enum.empty?(new_snapshots) do
      Mix.shell().info("""

      No new snapshots generated. Make sure your test includes html_snapshot() calls:

          use Excessibility

          test "page is accessible", %{conn: conn} do
            {:ok, view, _html} = live(conn, "/")
            html_snapshot(view)  # <-- Add this
          end
      """)

      exit({:shutdown, 0})
    end

    Mix.shell().info("\n## Accessibility Check\n")
    Mix.shell().info("Checking #{length(new_snapshots)} snapshot(s)...\n")

    run_axe(new_snapshots)
  end

  defp list_snapshots do
    snapshot_dir()
    |> Path.join("*.html")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))
    |> Enum.sort()
  end

  defp run_axe(files) do
    disable_rules = Application.get_env(:excessibility, :axe_disable_rules, [])
    opts = if disable_rules == [], do: [], else: [disable_rules: disable_rules]

    results =
      Enum.map(files, fn file ->
        file_url = "file://" <> Path.expand(file)
        result = Excessibility.AxeRunner.run(file_url, opts)
        {file, result}
      end)

    {passed, failed} =
      Enum.split_with(results, fn
        {_file, {:ok, %{violations: []}}} -> true
        {_file, {:ok, _}} -> false
        {_file, {:error, _}} -> false
      end)

    if length(failed) > 0 do
      Mix.shell().info("### Issues Found\n")

      Enum.each(failed, fn
        {file, {:ok, %{violations: violations}}} ->
          Mix.shell().info("**#{Path.basename(file)}**")
          format_violations(violations)

        {file, {:error, reason}} ->
          Mix.shell().info("**#{Path.basename(file)}**")
          Mix.shell().info("  Error: #{reason}\n")
      end)

      Mix.shell().info("\n#{length(failed)} file(s) with issues, #{length(passed)} passed")
      exit({:shutdown, 1})
    else
      Mix.shell().info("All #{length(passed)} snapshot(s) passed accessibility checks")
    end
  end

  defp format_violations(violations) do
    Enum.each(violations, fn violation ->
      impact = violation["impact"] || "unknown"
      id = violation["id"] || "unknown"
      description = violation["description"] || ""
      help_url = violation["helpUrl"] || ""
      nodes = violation["nodes"] || []

      Mix.shell().info("  [#{String.upcase(impact)}] #{id}: #{description}")

      if help_url != "" do
        Mix.shell().info("    Help: #{help_url}")
      end

      Mix.shell().info("    #{length(nodes)} element(s) affected\n")
    end)
  end

  defp snapshot_dir do
    Path.join([output_path(), "html_snapshots"])
  end

  defp output_path do
    Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
  end
end
