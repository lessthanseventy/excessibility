defmodule Excessibility.LiveViewBehaviourTest do
  use ExUnit.Case, async: true

  defmodule ProxyServer do
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
end
