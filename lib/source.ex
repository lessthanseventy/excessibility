defprotocol Excessibility.Source do
  @moduledoc """
  Protocol for extracting HTML from various test sources.

  Excessibility uses this protocol to support multiple test source types:

  - `Plug.Conn` - Phoenix controller test responses
  - `Wallaby.Session` - Browser-based feature test sessions
  - `Phoenix.LiveViewTest.View` - LiveView test views
  - `Phoenix.LiveViewTest.Element` - LiveView test elements

  ## Extending

  To add support for a custom source type, implement this protocol:

      defimpl Excessibility.Source, for: MyCustomSource do
        def to_html(source) do
          # Return HTML string or Floki-parsed tree
          MyCustomSource.get_html(source)
        end
      end
  """

  @doc """
  Converts a test source into HTML content.

  Returns either a binary HTML string or a Floki-parsed HTML tree.
  """
  @spec to_html(term()) :: binary() | tuple() | list(tuple())
  def to_html(source)
end

defimpl Excessibility.Source, for: Plug.Conn do
  def to_html(conn), do: Phoenix.ConnTest.html_response(conn, 200)
end

if Code.ensure_loaded?(Wallaby.Session) do
  defimpl Excessibility.Source, for: Wallaby.Session do
    def to_html(session) do
      mod = Application.get_env(:excessibility, :browser_mod, Wallaby.Browser)
      mod.page_source(session)
    end
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
