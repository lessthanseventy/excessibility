defmodule Excessibility do
  import Phoenix.ConnTest, only: [html_response: 2]
  alias Plug.Conn
  use Wallaby.DSL
  alias Wallaby.Session

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
  The html_snapshot/1 macro can be called to produce an HTML snapshot of any conn or Wallaby session that you pass to it. You can also pass a valid HTML string from a LiveViewTest. These can be used later to run pa11y against..It will return the conn or session that was passed in so that you can include it in a pipeline.

  ## Examples

      iex> Excessibility.html_snapshot(conn_or_session_or_html)
          conn_or_session
  """

  defmacro html_snapshot(conn_or_session_or_html) do
    quote do
      Excessibility.html_snapshot(unquote(conn_or_session_or_html), __ENV__, __MODULE__)
    end
  end

  @doc """
  The html_snapshot/2 macro can be called to produce an HTML snapshot of any conn or Wallaby session that you pass to it. You can also pass a valid HTML string from a LiveViewTest. The second argument should be an atom to tag the snapshot with. This can be passed to main_snapshot/2 to handle render_clicks and the like in LiveViewTests.

  ## Examples

      iex> Excessibility.html_snapshot(conn_or_session_or_html, tag)
          conn_or_session_or_html
  """

  defmacro html_snapshot(conn_or_session_or_html, tag) when is_atom(tag) do
    quote do
      Excessibility.html_snapshot(
        unquote(conn_or_session_or_html),
        unquote(tag),
        __ENV__,
        __MODULE__
      )
    end
  end

  defmacro html_snapshot(_conn_or_session_or_html, _tag) do
    raise ArgumentError,
      message: ~s"""
      the second argument to html_snapshot/2 must be an atom
      """
  end

  @doc """
  The main_snapshot/2 macro can be called with a valid html string and a tag. The tag should have a corresponding call to html_snapshot/2. This function will then replace the contents of the liveview in the html_snapshot with the html passed into main_snapshot. This is useful for handling functions like render_click in a LiveViewTest.

  ## Examples

      iex> Excessibility.main_snapshot(html, tag)
          html
  """

  defmacro main_snapshot(html, tag) do
    quote do
      Excessibility.main_snapshot(unquote(html), unquote(tag), __ENV__, __MODULE__)
    end
  end

  def html_snapshot(conn_or_session, env, module)
      when is_struct(conn_or_session, Conn)
      when is_struct(conn_or_session, Session) do
    filename = get_filename(env, module)

    get_html(conn_or_session)
    |> maybe_write_html(filename)

    conn_or_session
  end

  def html_snapshot(html, env, module) when is_binary(html) do
    filename = get_filename(env, module)

    html
    |> maybe_write_html(filename)

    html
  end

  def html_snapshot(conn_or_session_or_html, tag, env, module) do
    filename = get_filename(env, module, tag)

    conn_or_session_or_html
    |> maybe_write_html(filename)

    conn_or_session_or_html
  end

  def main_snapshot(html, tag, env, module) do
    filename = get_filename(env, module, tag)

    html
    |> replace_with_main(filename)

    html
  end

  defp get_html(%Element{} = _conn_or_session) do
    raise ArgumentError,
      message: ~s"""
      html_snapshot/1 cannot be called with an %Element{}
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
    |> Floki.parse_document!()
    |> Floki.raw_html(pretty: true)
  end

  defp get_html(%Session{} = session) do
    Wallaby.Browser.page_source(session)
  end

  defp maybe_write_html(html, filename) do
    html =
      html
      |> validate_html()
      |> relativize_asset_paths()

    File.mkdir_p("#{@snapshots_path}")

    Path.join([File.cwd!(), "#{@snapshots_path}", filename])
    |> File.write(html, [:write])
  end

  defp replace_with_main(html, filename) do
    file_contents =
      Path.join([File.cwd!(), "#{@snapshots_path}", filename])
      |> File.read!()
      |> Floki.parse_document!()

    {:ok, [{"main", attrs, children}]} = Floki.parse_fragment(html)

    contents =
      file_contents
      |> Floki.traverse_and_update(fn
        {"main", _attrs, _children} ->
          {"main", attrs, children}

        other ->
          other
      end)
      |> Floki.raw_html(pretty: true)

    Path.join([File.cwd!(), "#{@snapshots_path}", filename])
    |> File.write(contents, [:write])
  end

  defp validate_html(html) do
    html
    |> Floki.parse_document!()
    |> Floki.raw_html(pretty: true)
  end

  defp get_filename(_env, module, tag) when is_atom(tag) do
    "#{module |> get_module_name()}_#{tag}.html"
    |> String.replace(" ", "_")
  end

  defp get_filename(env, module) do
    "#{module |> get_module_name()}_#{env.line}.html"
    |> String.replace(" ", "_")
  end

  defp get_module_name(module) do
    module |> Atom.to_string() |> String.downcase() |> String.splitter(".") |> Enum.take(-1)
  end

  defp relativize_asset_paths(html) do
    html
    |> String.replace("\"/assets/js/", "\"./assets/js/")
    |> String.replace("\"/assets/css/", "\"./assets/css/")
  end
end
