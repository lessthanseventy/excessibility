defprotocol Excessibility.Source do
  @doc """
  Converts a source (Conn, Session, LiveView View/Element) into an HTML string or parsed HTML tree.
  """
  @spec to_html(term()) :: binary() | tuple() | list(tuple())
  def to_html(source)
end

defimpl Excessibility.Source, for: Plug.Conn do
  def to_html(conn), do: Phoenix.ConnTest.html_response(conn, 200)
end

defimpl Excessibility.Source, for: Wallaby.Session do
  def to_html(session) do
    mod = Application.get_env(:excessibility, :browser_mod, Wallaby.Browser)
    mod.page_source(session)
  end
end

defimpl Excessibility.Source, for: Phoenix.LiveViewTest.View do
  def to_html(view) do
    mod = Application.get_env(:excessibility, :live_view_mod, Excessibility.LiveView)
    mod.render_tree(view)
  end
end

defimpl Excessibility.Source, for: Phoenix.LiveViewTest.Element do
  def to_html(element), do: Excessibility.LiveView.render_tree(element)
end
