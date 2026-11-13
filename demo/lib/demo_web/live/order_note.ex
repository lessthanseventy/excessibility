defmodule DemoWeb.OrderNote do
  @moduledoc """
  A stateful component per order row, so the page carries LiveView's
  component ids.
  """
  use DemoWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <span id={@id} class="note">Ref {@order.ref}</span>
    """
  end
end
