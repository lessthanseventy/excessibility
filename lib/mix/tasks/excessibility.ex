defmodule Mix.Tasks.Excessibility do
  @moduledoc "Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby."
  @shortdoc "Runs pally against generated snapshots"
  @requirements ["app.config"]
  @pally_path Application.compile_env(
                :excessibility,
                :pa11y_path,
                "assets/node_modules/pa11y/bin/pa11y.js"
              )
  @output_path Application.compile_env(
                 :excessibility,
                 :excessibility_output_path,
                 "test/excessibility"
               )
  @snapshots_path "#{@output_path}/html_snapshots"

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    File.ls!(@snapshots_path)
    |> filter_dirs()
    |> run_pa11y()
    |> print_results()
    |> exit_status()
  end

  defp filter_dirs(list_of_files) do
    list_of_files
    |> Enum.filter(fn file ->
      file
      |> String.contains?(".html")
    end)
  end

  defp run_pa11y(list_of_files) do
    list_of_files
    |> Enum.map(fn file ->
      file_path = "#{File.cwd!()}/" <> "#{@snapshots_path}/" <> file
      pally = "#{File.cwd!()}/#{@pally_path}"

      System.cmd("sh", ["-c", "#{pally} #{file_path}"])
    end)
    |> Enum.sort(fn {_res_one, status_one}, {_res_two, status_two} ->
      status_one < status_two
    end)
  end

  defp exit_status(results) do
    results
    |> Enum.all?(fn {_, status} -> status == 0 end)
    |> if do
      System.stop(0)
    else
      if Mix.env() !== :test do
        System.halt(1)
      end
    end
  end

  defp print_results(results) do
    results
    |> Enum.each(fn {result, _status} ->
      IO.puts(result)
    end)

    results
  end
end
