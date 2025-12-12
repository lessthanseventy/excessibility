defmodule Mix.Tasks.Excessibility do
  @moduledoc "Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby."
  @shortdoc "Runs pally against generated snapshots"
  @requirements ["app.config"]

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    snapshot_dir = Path.join(["test", "excessibility", "html_snapshots"])

    snapshot_dir
    |> Path.join("*.html")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))
    |> Enum.each(fn file ->
      file_url = "file://" <> Path.expand(file)

      Mix.shell().info("🔍 Running Pa11y on #{file_url}...")

      {output, status} =
        System.cmd("node", [pa11y_path(), file_url], stderr_to_stdout: true)

      IO.puts(output)

      if status != 0 do
        Mix.shell().error("❌ Pa11y failed on #{file}")
      end
    end)
  end

  defp pa11y_path do
    Application.get_env(:excessibility, :pa11y_path) ||
      Path.join([
        Mix.Project.deps_paths()[:excessibility],
        "assets/node_modules/pa11y/bin/pa11y.js"
      ])
  end
end
