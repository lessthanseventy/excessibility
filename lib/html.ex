defmodule Excessibility.HTML do
  @moduledoc """
  HTML parsing, wrapping, and static asset path handling.

  This module transforms partial HTML (like LiveView renders or controller
  responses) into complete, standalone HTML documents suitable for Pa11y analysis.

  ## Responsibilities

  - Wrapping partial HTML in complete document structure
  - Extracting `<head>` content from the Phoenix endpoint
  - Prefixing static asset paths with `file://` for local Pa11y access
  - Removing scripts (which can't execute in static snapshots)

  This module is used internally by `Excessibility.Snapshot` and typically
  doesn't need to be called directly.
  """

  @type html_tree :: tuple() | list(tuple())

  @doc """
  Wraps HTML content in a complete document structure if needed.

  Accepts either a binary string or a parsed Floki HTML tree.
  Returns a complete HTML document as a string with proper attributes.
  """
  @spec wrap(binary() | html_tree()) :: binary()
  def wrap(raw_content) do
    static_path = build_static_path()

    wrapped =
      cond do
        is_binary(raw_content) ->
          Floki.parse_document!(raw_content)

        match?({"html", _, _}, raw_content) ->
          raw_content

        match?({"div", _, _}, raw_content) and contains_phx_main?(raw_content) ->
          {head, html_attrs} = app_head_and_html_attrs()
          {"html", html_attrs, [head, {"body", [], [raw_content]}]}

        true ->
          {head, html_attrs} = app_head_and_html_attrs()
          {"html", html_attrs, [head, {"body", [], List.wrap(raw_content)}]}
      end

    wrapped
    |> Floki.traverse_and_update(&prefix_paths(&1, static_path))
    |> Floki.raw_html(pretty: true)
  end

  defp app_head_and_html_attrs do
    path = Application.get_env(:excessibility, :head_render_path, "/")

    conn =
      :get
      |> Plug.Test.conn(path)
      |> app_endpoint().call([])

    body = conn.resp_body
    doc = Floki.parse_document!(body)

    head =
      case Floki.find(doc, "head") do
        [h | _] -> h
        _ -> {"head", [], []}
      end

    html_attrs =
      case doc do
        [{"html", attrs, _children} | _] -> attrs
        _ -> []
      end

    {head, html_attrs}
  end

  defp contains_phx_main?(tree) do
    case Floki.attribute(tree, "data-phx-main") do
      [] -> false
      _ -> true
    end
  end

  defp build_static_path do
    Path.join(Mix.Project.app_path(), "priv/static")
  end

  defp prefix_paths({"script", _, _}, _), do: nil
  defp prefix_paths({"a", _, _} = link, _), do: link

  defp prefix_paths({el, attrs, children}, static_path) do
    {el, maybe_prefix_static_path(attrs, static_path), children}
  end

  defp prefix_paths(el, _), do: el

  defp maybe_prefix_static_path(attrs, nil), do: attrs

  defp maybe_prefix_static_path(attrs, static_path) do
    Enum.map(attrs, fn
      {"src", path} -> {"src", prefix_static_path(path, static_path)}
      {"href", path} -> {"href", prefix_static_path(path, static_path)}
      attr -> attr
    end)
  end

  defp prefix_static_path("//" <> _ = url, _), do: url
  defp prefix_static_path("/" <> _ = path, prefix), do: "file://" <> Path.join([prefix, path])
  defp prefix_static_path(url, _), do: url

  defp app_endpoint do
    Application.get_env(:excessibility, :endpoint) ||
      raise """
      Excessibility requires a configured Phoenix endpoint.

      Please set this in your config.exs:

          config :excessibility, :endpoint, MyAppWeb.Endpoint
      """
  end
end
