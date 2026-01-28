defmodule Mix.Tasks.Excessibility do
  @shortdoc "Run accessibility checks on snapshots"

  @moduledoc """
  Runs Pa11y accessibility checks on HTML snapshots.

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

  - `:pa11y_path` - Custom path to Pa11y executable (auto-detected by default)
  - `:pa11y_config` - Path to pa11y.json config file (default: `"pa11y.json"`)
  - `:excessibility_output_path` - Base directory for snapshots (default: `"test/excessibility"`)

  ## Pa11y Configuration

  If a `pa11y.json` file exists in your project root, it will be passed to Pa11y
  via the `--config` flag. Use this to ignore specific WCAG rules:

      {
        "ignore": [
          "WCAG2AA.Principle3.Guideline3_2.3_2_2.H32.2"
        ]
      }

  ## Prerequisites

  Run `mix excessibility.install` first to install Pa11y via npm.
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run([]) do
    # No args - check all existing snapshots
    run_pa11y_on_all()
  end

  def run(args) do
    # With args - run tests first, then check new snapshots
    run_tests_then_check(args)
  end

  defp run_pa11y_on_all do
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
    run_pa11y(files)
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

    run_pa11y(new_snapshots)
  end

  defp list_snapshots do
    snapshot_dir()
    |> Path.join("*.html")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))
    |> Enum.sort()
  end

  defp run_pa11y(files) do
    pa11y = pa11y_path()

    unless File.exists?(pa11y) do
      Mix.shell().error("""
      Pa11y not found at #{pa11y}.

      Run `mix excessibility.install` first.
      """)

      exit({:shutdown, 1})
    end

    config_args = pa11y_config_args()

    results =
      Enum.map(files, fn file ->
        file_url = "file://" <> Path.expand(file)
        {output, status} = System.cmd("node", [pa11y | config_args] ++ [file_url], stderr_to_stdout: true)
        {file, status, output}
      end)

    {passed, failed} = Enum.split_with(results, fn {_file, status, _output} -> status == 0 end)

    if length(failed) > 0 do
      Mix.shell().info("### Issues Found\n")

      Enum.each(failed, fn {file, _status, output} ->
        Mix.shell().info("**#{Path.basename(file)}**")
        Mix.shell().info(output)
      end)

      Mix.shell().info("\n#{length(failed)} file(s) with issues, #{length(passed)} passed")
      exit({:shutdown, 1})
    else
      Mix.shell().info("All #{length(passed)} snapshot(s) passed accessibility checks")
    end
  end

  defp snapshot_dir do
    Path.join([output_path(), "html_snapshots"])
  end

  defp output_path do
    Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
  end

  defp pa11y_path do
    Application.get_env(:excessibility, :pa11y_path) ||
      Path.join([dependency_root(), "assets/node_modules/pa11y/bin/pa11y.js"])
  end

  defp pa11y_config_args do
    config_path = Application.get_env(:excessibility, :pa11y_config, "pa11y.json")

    if File.exists?(config_path) do
      ["--config", config_path]
    else
      []
    end
  end

  defp dependency_root do
    Mix.Project.deps_paths()[:excessibility] || File.cwd!()
  end
end
