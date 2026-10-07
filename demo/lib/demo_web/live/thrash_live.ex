defmodule DemoWeb.ThrashLive do
  @moduledoc """
  Deliberately broken: a `tick` event re-assigns the SAME value every time,
  so each render repaints identical state. These are genuinely wasted renders
  (nothing changed since the previous render) — distinct from the healthy
  `render_click`-after-real-change case, which the analyzer must NOT flag.
  It also carries a `config` assign that is set at mount and never changes
  (dead state).
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:status, "ready")
     |> assign(:config, %{theme: "dark", locale: "en"})}
  end

  @impl true
  def handle_event("tick", _params, socket) do
    # Re-assign the identical value — a no-op that still forces a render.
    {:noreply, assign(socket, :status, "ready")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Thrash</h1>
    <p id="status">{@status}</p>
    <button phx-click="tick" type="button">Tick</button>
    """
  end
end
