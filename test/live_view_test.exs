defmodule Excessibility.LiveViewBehaviourTest do
  use ExUnit.Case, async: true

  defmodule ProxyServer do
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

  test "render_tree/1 renders from a LiveViewTest.View" do
    {:ok, proxy} = ProxyServer.start_link("<html><div>View</div></html>")

    view = %Phoenix.LiveViewTest.View{
      proxy: {nil, "topic", proxy},
      target: "target"
    }

    assert Excessibility.LiveView.render_tree(view) =~ "View"
  end

  test "render_tree/1 renders from a LiveViewTest.Element" do
    {:ok, proxy} = ProxyServer.start_link("<span>Element</span>")

    element = %Phoenix.LiveViewTest.Element{
      proxy: {nil, "topic", proxy}
    }

    assert Excessibility.LiveView.render_tree(element) =~ "Element"
  end

  describe "get_assigns/1" do
    defmodule FakeChannel do
      @moduledoc false
      use GenServer

      def start_link(state) do
        GenServer.start_link(__MODULE__, state)
      end

      @impl true
      def init(state), do: {:ok, state}
    end

    test "reads assigns from the LiveView process without calling the proxy" do
      {:ok, channel} = FakeChannel.start_link(%{socket: %{assigns: %{current_user: "andrew"}}})
      {:ok, proxy} = ProxyServer.start_link("<html></html>")

      view = %Phoenix.LiveViewTest.View{
        pid: channel,
        proxy: {nil, "topic", proxy},
        target: "target"
      }

      assert {:ok, %{current_user: "andrew"}} = Excessibility.LiveView.get_assigns(view)
      assert Process.alive?(proxy)
    end

    test "fails soft when the process state has no socket assigns" do
      {:ok, channel} = FakeChannel.start_link(:opaque_state)
      {:ok, proxy} = ProxyServer.start_link("<html></html>")

      view = %Phoenix.LiveViewTest.View{
        pid: channel,
        proxy: {nil, "topic", proxy},
        target: "target"
      }

      assert {:error, _} = Excessibility.LiveView.get_assigns(view)
      assert Process.alive?(proxy)
    end

    test "fails soft when the LiveView process is dead" do
      {:ok, channel} = FakeChannel.start_link(%{socket: %{assigns: %{}}})
      {:ok, proxy} = ProxyServer.start_link("<html></html>")
      GenServer.stop(channel)

      view = %Phoenix.LiveViewTest.View{
        pid: channel,
        proxy: {nil, "topic", proxy},
        target: "target"
      }

      assert {:error, _} = Excessibility.LiveView.get_assigns(view)
      assert Process.alive?(proxy)
    end

    test "returns an error for non-view input" do
      assert {:error, :invalid_view} = Excessibility.LiveView.get_assigns(:not_a_view)
    end
  end
end
