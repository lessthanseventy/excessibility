defmodule Excessibility.SourceTest do
  use ExUnit.Case

  import Mox

  setup :verify_on_exit!

  setup do
    Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveViewMock)
    Application.put_env(:excessibility, :browser_mod, Excessibility.BrowserMock)
    :ok
  end

  test "Plug.Conn returns HTML" do
    conn =
      :get
      |> Plug.Test.conn("/")
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(200, "<div>Hello</div>")

    assert Excessibility.Source.to_html(conn) =~ "Hello"
  end

  test "Wallaby.Session uses injected browser_mod" do
    session = %Wallaby.Session{id: "test"}

    expect(Excessibility.BrowserMock, :page_source, fn ^session -> "<html>Wallaby</html>" end)
    assert Excessibility.Source.to_html(session) =~ "Wallaby"
  end

  test "LiveView.View uses injected live_view_mod" do
    view = %Phoenix.LiveViewTest.View{proxy: {nil, nil, self()}}

    expect(Excessibility.LiveViewMock, :render_tree, fn ^view -> "<html>Mocked View</html>" end)
    assert Excessibility.Source.to_html(view) =~ "Mocked View"
  end
end
