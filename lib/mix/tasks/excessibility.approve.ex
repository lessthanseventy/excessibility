defmodule Mix.Tasks.Excessibility.Approve do
  @shortdoc "Approves snapshot diffs and updates the baseline"
  @moduledoc """
  Promotes snapshot diffs into the baseline directory.

  For every `*.bad.html`/`*.good.html` pair in the snapshot directory, this task
  either prompts for approval or automatically keeps the version passed through
  `--keep`.
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

    diffs =
      snapshots_dir()
      |> Path.join("*.bad.html")
      |> Path.wildcard()

    if diffs == [] do
      Mix.shell().info("No snapshot diffs pending approval in #{snapshots_dir()}")
    else
      Enum.each(diffs, &approve_diff(&1, keep))
    end
  end

  defp approve_diff(bad_path, keep) do
    filename = bad_path |> Path.basename() |> String.replace_suffix(".bad.html", ".html")
    snapshot_path = Path.join(snapshots_dir(), filename)
    good_path = String.replace_suffix(bad_path, ".bad.html", ".good.html")
    baseline_path = Path.join(baseline_dir(), filename)

    choice =
      keep ||
        prompt_choice("""
        Snapshot diff detected for #{filename}
        Approve (g)ood baseline or (b)ad new version? [g/b]:
        """)

    {html, label} =
      case choice do
        :good -> {File.read!(good_path), "good"}
        :bad -> {File.read!(bad_path), "bad"}
      end

    File.write!(baseline_path, html)
    File.write!(snapshot_path, html)
    File.rm_rf(good_path)
    File.rm_rf(bad_path)

    Mix.shell().info("✅ Approved #{label} snapshot for #{filename}")
  end

  defp prompt_choice(message) do
    message
    |> IO.gets()
    |> case do
      nil -> "b"
      input -> String.trim(String.downcase(input))
    end
    |> case do
      choice when choice in ["g", "good"] ->
        :good

      choice when choice in ["b", "bad"] ->
        :bad

      _ ->
        Mix.shell().info("Unrecognized response, defaulting to bad version.")
        :bad
    end
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
