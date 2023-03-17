defmodule Mix.Tasks.Excessibility do
  @moduledoc "Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby."
  @shortdoc "Runs pally against generated snapshots"
  @requirements ["app.config"]
  @assets_task Application.compile_env(:excessibility, :assets_task, "assets.deploy")
  @css_folder Application.compile_env(:excessibility, :css_folder, "priv/static/assets")
  @js_folder Application.compile_env(:excessibility, :js_folder, "priv/static/assets")
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

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run(@assets_task)

    File.mkdir_p("#{@ex_assets_path}/css/")
    File.mkdir_p("#{@ex_assets_path}/js/")

    File.cp!(app_css_path(), test_css_path())
    File.cp!(app_js_path(), test_js_path())

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
      System.halt(1)
    end
  end

  defp print_results(results) do
    results
    |> Enum.each(fn {result, _status} ->
      IO.puts(result)
    end)

    results
  end

  defp app_css_path(), do: "#{File.cwd!()}/#{@css_folder}/app.css"
  defp test_css_path(), do: "#{File.cwd!()}/#{@ex_assets_path}/css/app.css"
  defp app_js_path(), do: "#{File.cwd!()}/#{@js_folder}/app.js"
  defp test_js_path(), do: "#{File.cwd!()}/#{@ex_assets_path}/js/app.js"
end
