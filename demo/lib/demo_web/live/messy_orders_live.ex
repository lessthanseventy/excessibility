defmodule DemoWeb.MessyOrdersLive do
  @moduledoc """
  Deliberately broken, with the breakage on elements whose ids change on
  every mount: an unlabelled quantity input per order (axe `label`) and a
  clickable `<div>` per order (`phx_click_on_non_interactive`).

  The buyer's name is drawn at random, so a review scans both renders. The
  same violations are in both under different selectors, and
  `mix review.same_commit` must not report them as new.
  """
  use DemoWeb, :live_view

  @names ~w(Ada Grace Edsger Barbara Donald Margaret Alan Frances Dennis Radia Leslie Shafi)

  @impl true
  def mount(_params, _session, socket) do
    orders =
      for _ <- 1..3 do
        %{id: :rand.uniform(9_000_000), uuid: Ecto.UUID.generate(), name: Enum.random(@names)}
      end

    {:ok, assign(socket, :orders, orders)}
  end

  @impl true
  def handle_event("ship", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page">
      <h1>Orders to ship</h1>
      <ul>
        <li :for={order <- @orders}>
          Order {order.id} for {order.name}
          <input id={"qty-#{order.uuid}"} type="text" />
          <div id={"ship-#{order.id}"} phx-click="ship" phx-value-id={order.id}>Ship</div>
        </li>
      </ul>
    </main>
    """
  end
end
