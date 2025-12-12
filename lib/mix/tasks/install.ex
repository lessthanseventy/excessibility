defmodule Mix.Tasks.Excessibility.Install do
  @shortdoc "Installs JavaScript dependencies needed for Excessibility (e.g. pa11y)"
  @moduledoc """
  Installs vendored JavaScript dependencies for Excessibility.

  This runs `npm install` in the ./assets/ directory to install `pa11y`.
  """

  use Mix.Task

  @impl true
  def run(_args) do
    dep_path = Mix.Project.deps_paths()[:excessibility] || File.cwd!()
    assets_dir = Path.join(dep_path, "assets")

    unless File.exists?(Path.join(assets_dir, "package.json")) do
      Mix.shell().error("""
      Could not find package.json inside Excessibility dependency at #{assets_dir}.

      You may need to check out the full repo or clone it locally.
      """)

      exit({:shutdown, 1})
    end

    Mix.shell().info("Installing npm packages in #{assets_dir}...")

    {_, exit_code} =
      System.cmd("npm", ["install"], cd: assets_dir, into: IO.stream(:stdio, :line))

    if exit_code == 0 do
      Mix.shell().info("✔ pa11y installed in vendored assets/")
    else
      Mix.shell().error("npm install failed")
      exit({:shutdown, 1})
    end
  end
end
