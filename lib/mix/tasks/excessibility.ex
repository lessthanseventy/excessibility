defmodule Mix.Tasks.Excessibility do
  @shortdoc "Runs pally against generated snapshots"
  @moduledoc "Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby."
  use Mix.Task

  @requirements ["app.config"]
  @assets_task Application.compile_env(:excessibility, :assets_task, "assets.deploy")
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
  @ex_assets_path "#{@output_path}/assets"
  @max_failures Application.compile_env(
                  :excessibility,
                  :max_failures,
                  0
                )

  @max_percentage_failures Application.compile_env(
                             :excessibility,
                             :max_percentage_failures,
                             0
                           )

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run(@assets_task)

    File.mkdir_p("#{@ex_assets_path}/css/")
    File.mkdir_p("#{@ex_assets_path}/js/")
    File.mkdir_p("#{@snapshots_path}/")

    spinner_pid = spawn_link(fn -> spinner() end)

    @snapshots_path
    |> File.ls!()
    |> filter_dirs()
    |> run_pa11y()
    |> print_results()
    |> exit_status(@max_failures, @max_percentage_failures)

    Process.exit(spinner_pid, :normal)
  end

  defp filter_dirs(list_of_files) do
    Enum.filter(list_of_files, fn file -> String.contains?(file, ".html") end)
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

  defp exit_status(results, max_failures, max_percentage_failures) do
    total_tests = length(results)
    failures = Enum.filter(results, fn {_, status} -> status != 0 end)
    num_failures = length(failures)
    failure_percentage = num_failures / total_tests * 100

    if num_failures <= max_failures || failure_percentage <= max_percentage_failures do
      System.stop(0)
    else
      if Mix.env() !== :test do
        System.halt(1)
      end
    end
  end

  defp print_results(results) do
    Enum.each(results, fn {result, _status} -> IO.puts(result) end)
    results
  end

  defp spinner do
    spinner_chars = ["|", "/", "-", "\\"]
    spinner_index = 0
    IO.write("Testing for a11y violations, please wait:")
    IO.puts("\e[B")
    loop(spinner_chars, spinner_index)
  end

  defp loop(spinner_chars, spinner_index) do
    IO.ANSI.clear_line()
    IO.write("#{Enum.at(spinner_chars, spinner_index)}")
    # Adjust the sleep duration as needed
    :timer.sleep(300)
    clear_line()

    next_index =
      if spinner_index == 3 do
        0
      else
        spinner_index + 1
      end

    loop(spinner_chars, next_index)
  end

  defp clear_line do
    IO.write("\e[2K")
    IO.write("\r")
  end
end
