defmodule Mix.Tasks.Excessibility.Snapshots do
  @shortdoc "Manage accessibility snapshots"

  @moduledoc """
  List, clean, or open HTML snapshots.

  ## Usage

      # List all snapshots
      mix excessibility.snapshots

      # Delete all snapshots
      mix excessibility.snapshots --clean

      # Open a snapshot in the browser
      mix excessibility.snapshots --open snapshot_name.html
  """

  use Mix.Task

  @requirements ["app.config"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [clean: :boolean, open: :string])

    cond do
      Keyword.get(opts, :clean, false) -> clean_snapshots()
      open = Keyword.get(opts, :open) -> open_snapshot(open)
      true -> list_snapshots()
    end
  end

  defp list_snapshots do
    files = snapshot_files()

    if files == [] do
      Mix.shell().info("No snapshots found in #{snapshot_dir()}")
    else
      Mix.shell().info("#{length(files)} snapshot(s) in #{snapshot_dir()}\n")

      Enum.each(files, fn file ->
        %{size: size} = File.stat!(file)
        name = Path.basename(file)
        Mix.shell().info("  #{name} (#{format_size(size)})")
      end)
    end
  end

  defp clean_snapshots do
    files = snapshot_files()

    if files == [] do
      Mix.shell().info("No snapshots to clean.")
    else
      if Mix.shell().yes?("Delete #{length(files)} snapshot(s)?") do
        Enum.each(files, &File.rm!/1)
        Mix.shell().info("Deleted #{length(files)} snapshot(s).")
      end
    end
  end

  defp open_snapshot(name) do
    path =
      if String.contains?(name, "/") do
        name
      else
        Path.join(snapshot_dir(), name)
      end

    if File.exists?(path) do
      open_cmd =
        case :os.type() do
          {:unix, :darwin} -> "open"
          {:unix, _} -> "xdg-open"
          {:win32, _} -> "start"
        end

      System.cmd(open_cmd, [path])
    else
      Mix.shell().error("Snapshot not found: #{path}")
    end
  end

  defp snapshot_files do
    snapshot_dir()
    |> Path.join("*.html")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, [".bad.html", ".good.html"]))
    |> Enum.sort()
  end

  defp snapshot_dir do
    output_path =
      Application.get_env(:excessibility, :excessibility_output_path, "test/excessibility")

    Path.join(output_path, "html_snapshots")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes), do: "#{Float.round(bytes / 1024, 1)} KB"
end
