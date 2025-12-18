defmodule Excessibility.Snapshot do
  @moduledoc """
  Core snapshot generation, diffing, and file management.

  This module handles:

  - Converting test sources to HTML snapshots
  - Writing snapshots to the filesystem
  - Comparing snapshots against baselines
  - Interactive diff resolution
  - Screenshot generation via ChromicPDF

  ## File Locations

  By default, files are stored in:

  - `test/excessibility/html_snapshots/` - Current test snapshots
  - `test/excessibility/baseline/` - Approved baseline snapshots

  Configure with `:excessibility_output_path` to change the base directory.

  ## Diff Workflow

  When a snapshot differs from its baseline:

  1. `.good.html` (baseline) and `.bad.html` (new) files are created
  2. If `prompt_on_diff: true`, both files open and you choose which to keep
  3. The baseline is updated with your selection

  This module is typically used via the `Excessibility.html_snapshot/2` macro
  rather than called directly.
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
  Generates an HTML snapshot from a test source.

  ## Parameters

  - `source` - A `Plug.Conn`, `Wallaby.Session`, `Phoenix.LiveViewTest.View`,
    or `Phoenix.LiveViewTest.Element`
  - `env` - The `__ENV__` of the calling test (injected by macro)
  - `module` - The `__MODULE__` of the calling test (injected by macro)
  - `opts` - Keyword list of options

  ## Options

  - `:name` - Custom filename (default: `ModuleName_LineNumber.html`)
  - `:prompt_on_diff` - Interactively choose which snapshot to keep (default: `true`)
  - `:tag_on_diff` - Save `.good.html` and `.bad.html` on diff (default: `true`)
  - `:screenshot?` - Generate PNG screenshots (default: `false`)
  - `:open_browser?` - Open snapshot in browser after writing (default: `false`)
  - `:cleanup?` - Delete existing snapshots for this module first (default: `false`)

  ## Returns

  The original `source`, unchanged (for pipeline compatibility).
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
    baseline_path = Path.join([@baseline_path, filename])
    File.mkdir_p!(@baseline_path)

    case File.read(baseline_path) do
      {:ok, old_html} when old_html != new_html ->
        handle_snapshot_diff(old_html, new_html, path, filename, baseline_path, opts)

      {:ok, _same_html} ->
        :no_diff

      {:error, _reason} ->
        Logger.info("No baseline found for #{filename}, skipping diff")
    end

    write_snapshot_and_screenshot(new_html, path, opts)
    path
  end

  defp handle_snapshot_diff(old_html, new_html, path, filename, baseline_path, opts) do
    Logger.warning("Snapshot differs from baseline: #{filename}")

    if Keyword.get(opts, :tag_on_diff, true) do
      write_diff_files(path, old_html, new_html, opts)
    end

    if Keyword.get(opts, :prompt_on_diff, true) do
      prompt_for_diff_choice(path, old_html, new_html, baseline_path, filename)
    else
      Logger.info("Skipping diff prompt; baseline unchanged")
    end
  end

  defp write_diff_files(path, old_html, new_html, opts) do
    bad_path = String.replace(path, ".html", ".bad.html")
    good_path = String.replace(path, ".html", ".good.html")

    File.write!(bad_path, new_html)
    File.write!(good_path, old_html)

    if Keyword.get(opts, :screenshot?, false) do
      ensure_chromic_pdf_started()
      screenshot(screenshot_path(bad_path), new_html)
      screenshot(screenshot_path(good_path), old_html)
    end
  end

  defp prompt_for_diff_choice(path, old_html, new_html, baseline_path, filename) do
    Logger.warning("Prompting user to resolve diff")
    system_mod = Application.get_env(:excessibility, :system_mod, Excessibility.System)

    bad_path = String.replace(path, ".html", ".bad.html")
    good_path = String.replace(path, ".html", ".good.html")

    File.write!(bad_path, new_html)
    File.write!(good_path, old_html)

    system_mod.open_with_system_cmd(good_path)
    system_mod.open_with_system_cmd(bad_path)

    selected = prompt_user_choice(old_html, new_html, filename)
    File.write!(baseline_path, selected)

    result = if selected == old_html, do: "good", else: "bad"
    Logger.info("Updated baseline with #{result} version")
  end

  defp prompt_user_choice(old_html, new_html, filename) do
    IO.puts("\n[Excessibility] Snapshot differs from baseline: #{filename}")
    IO.puts("Choose which version to keep:")
    IO.puts("(g)ood (baseline) or (b)ad (new)?")

    user_choice = ">> " |> IO.gets() |> String.trim()

    case user_choice do
      "g" -> old_html
      "b" -> new_html
      _ -> new_html
    end
  end

  defp write_snapshot_and_screenshot(html, path, opts) do
    File.write!(path, html)
    Logger.info("Snapshot written to #{path}")

    if Keyword.get(opts, :screenshot?, false) do
      ensure_chromic_pdf_started()
      screenshot(screenshot_path(path), html)
    end
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
