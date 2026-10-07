defmodule DemoWeb.LeakyLive do
  @moduledoc """
  Deliberately broken: every click appends a ~120 KB blob to an assign that
  is never trimmed, and also appends to an unbounded `log` list. This is a
  genuine memory leak + unbounded growth — the analyzers SHOULD catch it,
  even after the issue #142 floors (the leak clears the absolute floor and
  the list grows well past a single element).
  """
  use DemoWeb, :live_view

  @blob String.duplicate("x", 120_000)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:history, [])
     |> assign(:log, [])
     |> assign(:clicks, 0)}
  end

  @impl true
  def handle_event("grow", _params, socket) do
    # Append a batch of log lines each click, so the unbounded list climbs
    # past 100 entries and trips data_growth's pagination critical.
    batch = for i <- 1..25, do: "entry #{socket.assigns.clicks}-#{i}"

    {:noreply,
     socket
     |> update(:history, &[@blob | &1])
     |> update(:log, &(batch ++ &1))
     |> update(:clicks, &(&1 + 1))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>Leaky</h1>
    <p id="clicks">Clicks: {@clicks}</p>
    <p id="log-size">Log entries: {length(@log)}</p>
    <button phx-click="grow" type="button">Grow</button>
    """
  end
end
