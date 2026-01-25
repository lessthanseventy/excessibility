defmodule Excessibility.Snapshot do
  @moduledoc """
  Core snapshot generation and file management.

  This module handles:

  - Converting test sources to HTML snapshots
  - Writing snapshots to the filesystem
  - Screenshot generation via ChromicPDF

  ## File Locations

  Snapshots are stored in `test/excessibility/html_snapshots/` by default.
  Configure with `:excessibility_output_path` to change the base directory.

  ## Workflow

  1. Run tests to generate snapshots
  2. Run `mix excessibility.baseline` to lock in a known-good state
  3. Run `mix excessibility.compare` to diff against baseline after changes

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
  - `:screenshot?` - Generate PNG screenshots (default: `false`)
  - `:open_browser?` - Open snapshot in browser after writing (default: `false`)
  - `:cleanup?` - Delete existing snapshots for this module first (default: `false`)

  ## Returns

  The original `source`, unchanged (for pipeline compatibility).
  """
  @spec html_snapshot(term(), Macro.Env.t(), module(), keyword()) :: term()
  def html_snapshot(source, env, module, opts \\ []) do
    if Keyword.get(opts, :cleanup?, false), do: cleanup_snapshots(module)

    html = Excessibility.Source.to_html(source)

    # Check if we're in auto-capture mode
    metadata = get_capture_metadata(source, opts)

    filename = get_filename(env, module, opts, metadata)
    path = Path.join([File.cwd!(), @snapshots_path, filename])
    File.mkdir_p!(@snapshots_path)

    html
    |> HTML.wrap()
    |> add_metadata(metadata)
    |> write_snapshot(path, opts)
    |> maybe_open_browser(opts)

    source
  end

  defp get_filename(env, module, opts, metadata) do
    cond do
      # Explicit name provided
      opts[:name] ->
        opts[:name]

      # Auto-capture mode with metadata
      metadata ->
        "#{metadata.test_name}_#{metadata.sequence}_#{metadata.event_type}.html"

      # Default: module_line.html
      true ->
        "#{module |> to_string() |> String.replace(".", "_")}_#{env.line}.html"
    end
  end

  defp get_capture_metadata(source, opts) do
    # Check if we're in auto-capture mode
    case Excessibility.Capture.get_state() do
      nil ->
        nil

      _state ->
        # Extract event type from opts or generate sequential name
        event_type = opts[:event_type] || generate_event_name(opts)

        # Extract assigns from source if it's a LiveView
        assigns = extract_assigns(source)

        Excessibility.Capture.record_event(event_type, assigns)
    end
  end

  defp generate_event_name(_opts) do
    # Generate a simple sequential event name
    state = Excessibility.Capture.get_state()

    case state.sequence do
      0 -> "initial"
      n -> "event_#{n + 1}"
    end
  end

  defp extract_assigns(%Phoenix.LiveViewTest.View{} = view) do
    # Access the LiveView module configured for this library
    live_view_mod = Application.get_env(:excessibility, :live_view_mod, Excessibility.LiveView)

    # Try to get assigns using the LiveView module
    case live_view_mod.get_assigns(view) do
      {:ok, assigns} when is_map(assigns) ->
        # Filter out internal Phoenix assigns to keep output clean
        assigns
        |> Map.drop([:flash, :live_action, :__changed__])
        |> Enum.reject(fn {k, _v} -> String.starts_with?(to_string(k), "_") end)
        |> Map.new()

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp extract_assigns(_), do: %{}

  defp add_metadata(html, nil), do: html

  defp add_metadata(html, metadata) do
    comment = """
    <!--
    Excessibility Snapshot
    Test: #{metadata.test_name}
    Sequence: #{metadata.sequence}
    Event: #{metadata.event_type}
    Timestamp: #{metadata.timestamp}
    Assigns: #{inspect(metadata.assigns)}
    Previous: #{metadata.previous || "none"}
    -->
    """

    comment <> "\n" <> html
  end

  defp write_snapshot(html, path, opts) do
    File.write!(path, html)
    Logger.info("Snapshot written to #{path}")

    if Keyword.get(opts, :screenshot?, false) do
      ensure_chromic_pdf_started()
      screenshot(screenshot_path(path), html)
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
