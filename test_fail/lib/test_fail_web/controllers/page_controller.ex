defmodule TestFailWeb.PageController do
  use TestFailWeb, :controller

  def fail(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :fail, layout: false)
  end
end
