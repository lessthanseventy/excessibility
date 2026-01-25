defmodule Mix.Tasks.Excessibility.Compare do
  @shortdoc "Compares snapshots against baseline and resolves diffs"
  @moduledoc """
  Compares current snapshots against the baseline and prompts for resolution.

  For each snapshot that differs from its baseline, this task:

  1. Creates `.good.html` (baseline) and `.bad.html` (new) files
  2. Opens both in your browser for comparison
  3. Prompts you to choose which version to keep
  4. Updates the baseline with your choice

  ## Usage

      # Interactive mode - prompts for each diff
      $ mix excessibility.compare

      # Keep all baseline (good) versions
      $ mix excessibility.compare --keep good

      # Accept all new (bad) versions as baseline
      $ mix excessibility.compare --keep bad

  ## Options

  - `--keep good` - Automatically keep all baseline versions (no changes)
  - `--keep bad` - Automatically accept all new versions as baseline

  ## Workflow

  1. Run your tests to generate snapshots
  2. Run this task to compare against baseline
  3. Review diffs and choose which to keep
  4. The selected version becomes the new baseline
  """
  use Mix.Task

  @requirements ["app.config"]

  @impl true
  def run(args) do
    {opts, _argv, _invalid} =
      OptionParser.parse(args,
        strict: [keep: :string]
      )

    keep =
      case opts[:keep] do
        nil -> nil
        "good" -> :good
        "bad" -> :bad
        other -> raise ArgumentError, "Unknown --keep value #{inspect(other)}. Use good or bad."
      end

    ensure_directories!()

    snapshots =
      snapshots_dir()
      |> Path.join("*.html")
      |> Path.wildcard()
      |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))

    if snapshots == [] do
      Mix.shell().info("No snapshots found in #{snapshots_dir()}")
      exit({:shutdown, 0})
    end

    diffs = Enum.filter(snapshots, &differs_from_baseline?/1)

    if diffs == [] do
      Mix.shell().info("All #{length(snapshots)} snapshot(s) match baseline.")
    else
      Mix.shell().info("Found #{length(diffs)} diff(s) out of #{length(snapshots)} snapshot(s).\n")
      Enum.each(diffs, &resolve_diff(&1, keep))
      cleanup_diff_files()
    end
  end

  defp differs_from_baseline?(snapshot_path) do
    filename = Path.basename(snapshot_path)
    baseline_path = Path.join(baseline_dir(), filename)

    case File.read(baseline_path) do
      {:ok, baseline_html} ->
        {:ok, snapshot_html} = File.read(snapshot_path)
        baseline_html != snapshot_html

      {:error, :enoent} ->
        Mix.shell().info("No baseline for #{filename} - run `mix excessibility.baseline` first")
        false
    end
  end

  defp resolve_diff(snapshot_path, keep) do
    filename = Path.basename(snapshot_path)
    baseline_path = Path.join(baseline_dir(), filename)

    {:ok, new_html} = File.read(snapshot_path)
    {:ok, old_html} = File.read(baseline_path)

    bad_path = String.replace(snapshot_path, ".html", ".bad.html")
    good_path = String.replace(snapshot_path, ".html", ".good.html")

    File.write!(bad_path, new_html)
    File.write!(good_path, old_html)

    choice =
      keep ||
        prompt_choice(filename, good_path, bad_path)

    case choice do
      :good ->
        Mix.shell().info("Kept baseline for #{filename}")

      :bad ->
        File.write!(baseline_path, new_html)
        Mix.shell().info("Updated baseline for #{filename}")
    end
  end

  defp prompt_choice(filename, good_path, bad_path) do
    system_mod = Application.get_env(:excessibility, :system_mod, Excessibility.System)
    system_mod.open_with_system_cmd(good_path)
    system_mod.open_with_system_cmd(bad_path)

    """
    Diff: #{filename}
    (g)ood = baseline, (b)ad = new version
    Keep which? [g/b]:
    """
    |> IO.gets()
    |> parse_choice()
  end

  defp parse_choice(input) do
    input
    |> case do
      nil -> "b"
      str -> String.trim(String.downcase(str))
    end
    |> case do
      choice when choice in ["g", "good"] ->
        :good

      choice when choice in ["b", "bad"] ->
        :bad

      _ ->
        Mix.shell().info("Unrecognized response, defaulting to bad (new version).")
        :bad
    end
  end

  defp cleanup_diff_files do
    snapshots_dir()
    |> Path.join("*.{good,bad}.html")
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)
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
