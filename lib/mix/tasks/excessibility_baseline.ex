defmodule Mix.Tasks.Excessibility.Baseline do
  @shortdoc "Locks current snapshots as the baseline"
  @moduledoc """
  Copies current snapshots to the baseline directory.

  Use this command when your snapshots represent a known-good state
  that you want to compare against in the future.

  ## Usage

      $ mix excessibility.baseline

  ## Workflow

  1. Run your tests to generate snapshots
  2. Verify snapshots are correct (run `mix excessibility` for Pa11y checks)
  3. Run this task to lock them as baseline
  4. After code changes, run `mix excessibility.compare` to see what changed
  """
  use Mix.Task

  @requirements ["app.config"]

  @impl true
  def run(_args) do
    ensure_directories!()

    snapshots =
      snapshots_dir()
      |> Path.join("*.html")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))

    if snapshots == [] do
      Mix.shell().error("No snapshots found in #{snapshots_dir()}")
      Mix.shell().info("Run your tests first to generate snapshots.")
      exit({:shutdown, 1})
    end

    Enum.each(snapshots, fn snapshot_path ->
      filename = Path.basename(snapshot_path)
      baseline_path = Path.join(baseline_dir(), filename)
      File.cp!(snapshot_path, baseline_path)
      Mix.shell().info("Baseline set: #{filename}")
    end)

    Mix.shell().info("\n#{length(snapshots)} snapshot(s) locked as baseline.")
  end

  defp ensure_directories! do
    File.mkdir_p!(snapshots_dir())
    File.mkdir_p!(baseline_dir())
  end

  defp snapshots_dir do
    Path.join(output_path(), "html_snapshots")
  end

  defp baseline_dir do
    Path.join(output_path(), "baseline")
  end

  defp output_path do
    Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")
  end
end
