defmodule DemoWeb.FloodLive do
  @moduledoc """
  Deliberately broken: floods itself with `:tick` messages (as a PubSub- or
  timer-heavy LiveView would). LiveView emits no handle_info telemetry, so
  these are only visible because the `Excessibility.TelemetryCapture` on_mount
  hook is wired in the router's live_session — then message_flooding catches
  the burst (issue #147).
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: flood()
    {:ok, assign(socket, :ticks, 0)}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, update(socket, :ticks, &(&1 + 1))}

  defp flood, do: for(_ <- 1..30, do: send(self(), :tick))

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Flood</h1>
    <p id="ticks">Ticks: {@ticks}</p>
    """
  end
end
