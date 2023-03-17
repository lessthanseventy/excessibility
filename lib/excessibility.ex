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
  The here function is the meat of the package. Calling htis macro will produce an HTML snapshot of any conn or Wallaby session that you pass to it. These can be used later to run pa11y against..It will return the conn or session that was passed in so that you can include it in a pipeline.

  ## Examples

      iex> Excessibility.html_snapshot(conn_or_session)
          conn_or_session
  """

  defmacro html_snapshot(conn_or_session) do
    quote do
      Excessibility.html_snapshot(unquote(conn_or_session), __ENV__, __MODULE__)
    end
  end

  def html_snapshot(conn_or_session, env, module) do
    filename = get_filename(env, module)

    get_html(conn_or_session)
    |> write_html(filename)

    conn_or_session
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

  defp write_html(html, filename) do
    html =
      html
      |> relativize_asset_paths()

    Path.join([File.cwd!(), "#{@output_path}", filename])
    |> File.write(html, [:write])
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
