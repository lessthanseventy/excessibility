defmodule DemoWeb.OrdersLive do
  @moduledoc """
  An accessible page whose data is different on every mount, the way a test
  suite's factories make it: integer ids, UUIDs in DOM ids, a display id cut
  from the UUID, sequenced emails. Around the table sits what a real page
  renders fresh each time: a CSRF form and link, a signed token in a URL, an
  upload input, a stream, a live component per row and a clock. The dialog
  fades in over 300ms and the sync indicator animates forever.

  The buyer's name is drawn at random, as Faker would: that is a real text
  difference, so a review lists the page as changed and runs axe on both
  renders, mid-fade included. None of it is a problem the change introduced,
  so `mix review.same_commit` must report no findings for it.
  """
  use DemoWeb, :live_view

  @names ~w(Ada Grace Edsger Barbara Donald Margaret Alan Frances Dennis Radia Leslie Shafi)

  @impl true
  def mount(_params, _session, socket) do
    orders = for _ <- 1..3, do: order()

    {:ok,
     socket
     |> assign(orders: orders, confirming: hd(orders), now: DateTime.utc_now())
     |> assign(:share_token, Phoenix.Token.sign(DemoWeb.Endpoint, "share", hd(orders).id))
     |> allow_upload(:receipt, accept: ~w(.pdf))
     |> stream(:events, for(order <- orders, do: %{id: order.id, text: "Order #{order.id} paid"}))}
  end

  @impl true
  def handle_event("confirm", %{"id" => id}, socket) do
    {:noreply,
     assign(socket, :confirming, Enum.find(socket.assigns.orders, &(to_string(&1.id) == id)))}
  end

  def handle_event("close", _params, socket), do: {:noreply, assign(socket, :confirming, nil)}

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page">
      <h1>Orders</h1>

      <p>Updated at {Calendar.strftime(@now, "%H:%M:%S")}</p>
      <p class="spinner" role="status">Syncing</p>

      <.form for={%{}} action={~p"/review/orders"} method="post">
        <label for="search">Search orders</label>
        <input id="search" name="q" type="text" />
        <button type="submit">Search</button>
      </.form>

      <p>
        <.link href={~p"/review/orders?#{[token: @share_token]}"}>Share this list</.link>
        <.link href={~p"/review/orders"} method="delete">Clear filters</.link>
      </p>

      <form id="receipt-form" phx-change="validate" phx-drop-target={@uploads.receipt.ref}>
        <label for={@uploads.receipt.ref}>Attach a receipt</label>
        <.live_file_input upload={@uploads.receipt} />
      </form>

      <table>
        <caption>Open orders</caption>
        <thead>
          <tr>
            <th scope="col">Order</th>
            <th scope="col">Reference</th>
            <th scope="col">Buyer</th>
            <th scope="col">Actions</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={order <- @orders} id={"order-#{order.uuid}"}>
            <td>Order {order.id}</td>
            <td>Ref {order.ref}</td>
            <td>
              {order.name}, {order.email}
              <.live_component module={DemoWeb.OrderNote} id={"note-#{order.uuid}"} order={order} />
            </td>
            <td>
              <button
                type="button"
                phx-click="confirm"
                phx-value-id={order.id}
                aria-label={"Ship order #{order.id}"}
              >
                Ship
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      <h2>Activity</h2>
      <ul id="events" phx-update="stream">
        <li :for={{dom_id, event} <- @streams.events} id={dom_id}>{event.text}</li>
      </ul>

      <div
        :if={@confirming}
        class="dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
      >
        <h2 id="confirm-title">Ship order {@confirming.id}?</h2>
        <button type="button" class="button--primary" phx-click="close">Ship it</button>
        <button type="button" class="button--secondary" phx-click="close">Cancel</button>
      </div>
    </main>
    """
  end

  defp order do
    uuid = Ecto.UUID.generate()

    %{
      id: :rand.uniform(9_000_000),
      name: Enum.random(@names),
      uuid: uuid,
      ref: String.slice(uuid, 0, 6),
      email: "buyer-#{System.unique_integer([:positive])}@example.com"
    }
  end
end
