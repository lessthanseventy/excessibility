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

  test "LiveView.Element calls LiveView.render_tree directly" do
    # Set up a minimal GenServer to handle the proxy call
    {:ok, proxy} =
      Agent.start_link(fn -> "<span>Element Content</span>" end)

    # Create a GenServer that responds to LiveView protocol
    defmodule TestProxy do
      @moduledoc false
      use GenServer

      def start_link(response) do
        GenServer.start_link(__MODULE__, response)
      end

      @impl true
      def init(response), do: {:ok, response}

      @impl true
      def handle_call({:render_element, :find_element, _topic}, _from, response) do
        {:reply, {:ok, response}, response}
      end
    end

    {:ok, proxy_pid} = TestProxy.start_link("<span>Element HTML</span>")

    element = %Phoenix.LiveViewTest.Element{
      proxy: {nil, "topic", proxy_pid}
    }

    # The Element protocol implementation calls Excessibility.LiveView.render_tree directly
    # (not through the configurable live_view_mod)
    result = Excessibility.Source.to_html(element)
    assert result =~ "Element HTML"
  end
end
