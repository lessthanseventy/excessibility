defmodule Mix.Tasks.Excessibility do
  @moduledoc "Library to aid in testing your application for WCAG compliance automatically using Pa11y and Wallaby."
  @shortdoc "Runs pally against generated snapshots"
  @requirements ["app.config"]

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("assets.deploy")
    File.cp!(app_css_path(), test_css_path())
    File.cp!(app_js_path(), test_js_path())

    File.ls!("test/axe_html")
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
      file_path = "#{File.cwd!()}/" <> "test/axe_html/" <> file
      node_path = "#{File.cwd!()}/assets/node_modules/pa11y/bin/pa11y.js"

      System.cmd("sh", ["-c", "#{node_path} #{file_path}"])
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

  defp app_css_path(), do: "#{File.cwd!()}/priv/static/assets/css/app.css"
  defp test_css_path(), do: "#{File.cwd!()}/test/axe_html/assets/css/app.css"
  defp app_js_path(), do: "#{File.cwd!()}/priv/static/assets/js/app.js"
  defp test_js_path(), do: "#{File.cwd!()}/test/axe_html/assets/js/app.js"
end
