defmodule Excessibility.Snapshot do
  @moduledoc """
  Handles snapshot generation, file writing, naming, diffing, and screenshots.
  """

  alias Excessibility.HTML

  require Logger

  @output_path Application.compile_env(
                 :excessibility,
                 :excessibility_output_path,
                 "test/excessibility"
               )
  @snapshots_path Path.join(@output_path, "html_snapshots")
  @baseline_path Path.join(@output_path, "baseline")

  @doc """
  Produces a snapshot from a supported source.
  Options:
    * `:open_browser?` - open the snapshot in a browser (default: false)
    * `:cleanup?` - deletes existing snapshots for the current test module (default: false)
    * `:name` - custom filename (overrides default module/line-based name)
    * `:tag_on_diff` - if true, saves diffs as `.bad.html` or `.good.html` when mismatch occurs
    * `:prompt_on_diff` - interactively choose which snapshot to keep (default: true)
    * `:screenshot?` - generate screenshots of snapshot and baseline HTML (default: false)
  """
  @spec html_snapshot(term(), Macro.Env.t(), module(), keyword()) :: term()
  def html_snapshot(source, env, module, opts \\ []) do
    opts = Keyword.put_new(opts, :prompt_on_diff, true)
    if Keyword.get(opts, :cleanup?, false), do: cleanup_snapshots(module)

    html = Excessibility.Source.to_html(source)
    filename = get_filename(env, module, opts)
    path = Path.join([File.cwd!(), @snapshots_path, filename])
    File.mkdir_p!(@snapshots_path)

    html
    |> HTML.wrap()
    |> maybe_diff_and_write(path, filename, opts)
    |> maybe_open_browser(opts)

    source
  end

  defp get_filename(env, module, opts) do
    Keyword.get(opts, :name) ||
      "#{module |> to_string() |> String.replace(".", "_")}_#{env.line}.html"
  end

  defp maybe_diff_and_write(new_html, path, filename, opts) do
    system_mod = Application.get_env(:excessibility, :system_mod, Excessibility.System)
    baseline_path = Path.join([@baseline_path, filename])
    File.mkdir_p!(@baseline_path)

    if File.exists?(baseline_path) do
      old_html = File.read!(baseline_path)

      if old_html != new_html do
        Logger.warning("Snapshot differs from baseline: #{filename}")

        if Keyword.get(opts, :tag_on_diff, true) do
          bad_path = String.replace(path, ".html", ".bad.html")
          good_path = String.replace(path, ".html", ".good.html")

          File.write!(bad_path, new_html)
          File.write!(good_path, old_html)

          if Keyword.get(opts, :screenshot?, false) do
            ensure_chromic_pdf_started()
            bad_path |> screenshot_path() |> screenshot(new_html)
            good_path |> screenshot_path() |> screenshot(old_html)
          end
        end

        if Keyword.get(opts, :prompt_on_diff, true) do
          Logger.warning("Prompting user to resolve diff")

          bad_path = String.replace(path, ".html", ".bad.html")
          good_path = String.replace(path, ".html", ".good.html")

          File.write!(bad_path, new_html)
          File.write!(good_path, old_html)

          system_mod.open_with_system_cmd(good_path)
          system_mod.open_with_system_cmd(bad_path)

          IO.puts("\n[Excessibility] Snapshot differs from baseline: #{filename}")
          IO.puts("Choose which version to keep:")
          IO.puts("(g)ood (baseline) or (b)ad (new)?")

          user_choice = ">> " |> IO.gets() |> String.trim()

          selected =
            case user_choice do
              "g" -> old_html
              "b" -> new_html
              _ -> new_html
            end

          File.write!(baseline_path, selected)

          Logger.info("Updated baseline with #{if selected == old_html, do: "good", else: "bad"} version")
        else
          Logger.info("Skipping diff prompt; baseline unchanged")
        end
      end
    else
      Logger.info("No baseline found for #{filename}, skipping diff")
    end

    File.write!(path, new_html)
    Logger.info("Snapshot written to #{path}")

    if Keyword.get(opts, :screenshot?, false) do
      ensure_chromic_pdf_started()
      path |> screenshot_path() |> screenshot(new_html)
    end

    path
  end

  defp screenshot_path(path), do: String.replace(path, ".html", ".png")

  defp screenshot(output_path, html) do
    ChromicPDF.capture_screenshot({:html, html}, output: output_path)
    Logger.info("Wrote screenshot: #{output_path}")
  rescue
    e -> Logger.error("Screenshot failed: #{inspect(e)}")
  end

  defp ensure_chromic_pdf_started do
    case Process.whereis(ChromicPDF) do
      nil ->
        case ChromicPDF.start_link(name: ChromicPDF) do
          {:ok, _pid} ->
            Logger.info("ChromicPDF process started for Excessibility screenshots")

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            Logger.error("Could not start ChromicPDF: #{inspect(reason)}")
        end

      _pid ->
        :ok
    end
  rescue
    exception -> Logger.error("Could not ensure ChromicPDF is running: #{Exception.message(exception)}")
  end

  defp maybe_open_browser(path, opts) do
    if Keyword.get(opts, :open_browser?, false) do
      mod = Application.get_env(:excessibility, :system_mod, Excessibility.System)
      mod.open_with_system_cmd(path)
    end
  end

  defp cleanup_snapshots(module) do
    prefix = module |> to_string() |> String.replace(".", "_")

    @snapshots_path
    |> Path.join("#{prefix}_*.html")
    |> Path.wildcard()
    |> Enum.each(&File.rm/1)

    Logger.info("Old snapshots for #{module} cleaned up")
  end
end
