defmodule Mix.Tasks.Excessibility do
  @shortdoc "Runs Pa11y against generated snapshots"
  @moduledoc """
  Runs Pa11y accessibility checks against all generated HTML snapshots.

  ## Usage

      $ mix excessibility

  This task scans `test/excessibility/html_snapshots/` for `.html` files
  (excluding `.good.html` and `.bad.html` diff files) and runs Pa11y on each one.

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

  Run `mix igniter.install excessibility` first to install Pa11y via npm.
  """
  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(_args) do
    snapshot_dir = Path.join([output_path(), "html_snapshots"])
    pa11y = pa11y_path()

    unless File.exists?(pa11y) do
      Mix.shell().error("""
      Could not find Pa11y at #{pa11y}.

      Run `mix excessibility.install` first so Pa11y is installed locally, or set :pa11y_path in your config.
      """)

      exit({:shutdown, 1})
    end

    config_args = pa11y_config_args()

    files =
      snapshot_dir
      |> Path.join("*.html")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))

    if Enum.empty?(files) do
      Mix.shell().info("""
      No snapshots found in #{snapshot_dir}.

      Run your tests first to generate snapshots:

          mix test

      Then run this task again.
      """)
    end

    Enum.each(files, fn file ->
      file_url = "file://" <> Path.expand(file)

      Mix.shell().info("🔍 Running Pa11y on #{file_url}...")

      {output, status} =
        System.cmd("node", [pa11y | config_args] ++ [file_url], stderr_to_stdout: true)

      IO.puts(output)

      if status != 0 do
        Mix.shell().error("❌ Pa11y failed on #{file}")
      end
    end)
  end

  defp pa11y_config_args do
    config_path = Application.get_env(:excessibility, :pa11y_config, "pa11y.json")

    if File.exists?(config_path) do
      ["--config", config_path]
    else
      []
    end
  end

  defp pa11y_path do
    Application.get_env(:excessibility, :pa11y_path) ||
      Path.join([dependency_root(), "assets/node_modules/pa11y/bin/pa11y.js"])
  end

  defp output_path do
    Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
  end

  defp dependency_root do
    Mix.Project.deps_paths()[:excessibility] || File.cwd!()
  end
end
