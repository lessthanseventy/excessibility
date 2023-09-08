defmodule Excessibility do
  import Phoenix.ConnTest, only: [html_response: 2]
  alias Plug.Conn
  use Wallaby.DSL
  alias Wallaby.Session
  alias Phoenix.LiveViewTest.{DOM, View}
  alias Phoenix.LiveViewTest.Element, as: LiveElement

  @output_path Application.compile_env(
                 :excessibility,
                 :excessibility_output_path,
                 "test/excessibility"
               )
  @snapshots_path "#{@output_path}/html_snapshots"

  @moduledoc """
  Documentation for `Excessibility`.
  """

  @doc """
  Using the Excessibility macro will require the file for you.

  ## Examples

      use Excessibility

  """

  defmacro __using__(_opts) do
    quote do
      require Excessibility
    end
  end

  @doc """
  The html_snapshot macro can be called to produce an HTML snapshot of any of the following:
    - A Phoenix Conn
    - A Wallaby Session
    - A LiveViewTest View
    - A LiveViewTest Element
  These snapshots can then be used later to run pa11y against by calling the mix task..It will return the thing that was passed in so that you can include it in a pipeline.
  You can optionally pass a second argument of true to open the file in your browser for development purposes.

  ## Examples

      iex> Excessibility.html_snapshot(source, opts \\ [])
          source
  """

  defmacro html_snapshot(source, opts \\ []) do
    quote do
      Excessibility.html_snapshot(unquote(source), __ENV__, __MODULE__, unquote(opts))
    end
  end

  def html_snapshot(conn_or_session, env, module, opts)
      when is_struct(conn_or_session, Conn)
      when is_struct(conn_or_session, Session) do
    filename = get_filename(env, module)

    get_html(conn_or_session)
    |> maybe_wrap_html()
    |> write_html_file(filename)

    if Keyword.get(opts, :open_browser?, false) do
      open_with_system_cmd(filename)
    end

    conn_or_session
  end

  def html_snapshot(view_or_element, env, module, opts)
      when is_struct(view_or_element, View)
      when is_struct(view_or_element, LiveElement) do
    html = render_tree(view_or_element)
    filename = get_filename(env, module)

    view_or_element
    |> maybe_wrap_html(html)
    |> write_html_file(filename)

    if Keyword.get(opts, :open_browser?, false) do
      open_with_system_cmd(filename)
    end

    view_or_element
  end

  defp get_html(%Element{} = _conn_or_session) do
    raise ArgumentError,
      message: ~s"""
      html_snapshot/1 cannot be called with a Wallaby %Element{}
      Instead you can try something like:
      find(element, fn el ->
        el
        |> click_the_thing()
        |> assert_the_stuff()
      end)
      |> Excessibility.html_snapshot()
      """
  end

  defp get_html(%Conn{} = conn) do
    html_response(conn, 200)
  end

  defp get_html(%Session{} = session) do
    Wallaby.Browser.page_source(session)
  end

  defp get_filename(env, module) do
    "#{module |> get_module_name()}_#{env.line}.html"
    |> String.replace(" ", "_")
  end

  defp get_module_name(module) do
    module |> Atom.to_string() |> String.downcase() |> String.splitter(".") |> Enum.take(-1)
  end

  defp maybe_wrap_html(html) do
    build_path = Mix.Project.app_path()
    static_path = Path.join([build_path, "priv", "static"])

    html
    |> Floki.parse_document!()
    |> Floki.traverse_and_update(fn
      {"script", _, _} -> nil
      {"a", _, _} = link -> link
      {el, attrs, children} -> {el, maybe_prefix_static_path(attrs, static_path), children}
      el -> el
    end)
  end

  defp maybe_wrap_html(view_or_element, content) do
    {html, static_path} = call(view_or_element, :html)

    head =
      case DOM.maybe_one(html, "head") do
        {:ok, head} -> head
        _ -> {"head", [], []}
      end

    case Floki.attribute(content, "data-phx-main") do
      ["true" | _] ->
        # If we are rendering the main LiveView,
        # we return the full page html.
        html

      _ ->
        # Otherwise we build a basic html structure around the
        # view_or_element content.
        [
          {"html", [],
           [
             head,
             {"body", [],
              [
                content
              ]}
           ]}
        ]
    end
    |> Floki.traverse_and_update(fn
      {"a", _, _} = link -> link
      {el, attrs, children} -> {el, maybe_prefix_static_path(attrs, static_path), children}
      el -> el
    end)
  end

  defp maybe_prefix_static_path(attrs, nil), do: attrs

  defp maybe_prefix_static_path(attrs, static_path) do
    Enum.map(attrs, fn
      {"src", path} -> {"src", prefix_static_path(path, static_path)}
      {"href", path} -> {"href", prefix_static_path(path, static_path)}
      attr -> attr
    end)
  end

  defp prefix_static_path(<<"//" <> _::binary>> = url, _prefix), do: url

  defp prefix_static_path(<<"/" <> _::binary>> = path, prefix),
    do: "file://#{Path.join([prefix, path])}"

  defp prefix_static_path(url, _), do: url

  defp write_html_file(html, filename) do
    html = Floki.raw_html(html, pretty: true)

    Path.join([File.cwd!(), "#{@snapshots_path}", filename])
    |> File.write(html, [:write])
  end

  defp open_with_system_cmd(path) do
    cmd =
      case :os.type() do
        {:unix, :darwin} -> "open"
        {:unix, _} -> "xdg-open"
        {:win32, _} -> "start"
      end

    path = Path.join([File.cwd!(), "#{@snapshots_path}", path])
    System.cmd(cmd, [path])
  end

  defp render_tree(%View{} = view) do
    render_tree(view, {proxy_topic(view), "render", view.target})
  end

  defp render_tree(%LiveElement{} = element) do
    render_tree(element, element)
  end

  defp render_tree(view_or_element, topic_or_element) do
    call(view_or_element, {:render_element, :find_element, topic_or_element})
  end

  defp call(view_or_element, tuple) do
    try do
      GenServer.call(proxy_pid(view_or_element), tuple, 30_000)
    catch
      :exit, {{:shutdown, {kind, opts}}, _} when kind in [:redirect, :live_redirect] ->
        {:error, {kind, opts}}

      :exit, {{exception, stack}, _} ->
        exit({{exception, stack}, {__MODULE__, :call, [view_or_element]}})
    else
      :ok -> :ok
      {:ok, result} -> result
      {:raise, exception} -> raise exception
    end
  end

  defp proxy_pid(%{proxy: {_ref, _topic, pid}}), do: pid
  defp proxy_topic(%{proxy: {_ref, topic, _pid}}), do: topic
end
