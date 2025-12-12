defmodule Mix.Tasks.Excessibility do
  @shortdoc "Runs pally against generated snapshots"
  @moduledoc "Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby."
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

    snapshot_dir
    |> Path.join("*.html")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))
    |> Enum.each(fn file ->
      file_url = "file://" <> Path.expand(file)

      Mix.shell().info("🔍 Running Pa11y on #{file_url}...")

      {output, status} =
        System.cmd("node", [pa11y, file_url], stderr_to_stdout: true)

      IO.puts(output)

      if status != 0 do
        Mix.shell().error("❌ Pa11y failed on #{file}")
      end
    end)
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
