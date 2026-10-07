defmodule DemoWeb.NPlusOneLive do
  @moduledoc """
  Deliberately broken: `load` fires one query for a list, then one query per
  row — the classic N+1. Ecto emits `[:demo, :repo, :query]` telemetry for
  each; this view emits that exact event (no DB needed — the capture layer
  cannot distinguish a real query from the telemetry it produces), so
  ecto_query_analysis should catch the N+1 (issue #147).
  """
  use DemoWeb, :live_view

  @rows 14

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :loaded, 0)}

  @impl true
  def handle_event("load", _params, socket) do
    # 1 query for the collection...
    query("SELECT * FROM products", "products")
    # ...then one per row (the N+1).
    for id <- 1..@rows, do: query("SELECT * FROM categories WHERE id = #{id}", "categories")

    {:noreply, assign(socket, :loaded, @rows + 1)}
  end

  defp query(sql, source) do
    :telemetry.execute(
      [:demo, :repo, :query],
      %{total_time: System.convert_time_unit(1, :millisecond, :native)},
      %{source: source, query: sql, repo: Demo.Repo}
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <h1>N+1</h1>
    <p id="loaded">Queries: {@loaded}</p>
    <button phx-click="load" type="button">Load</button>
    """
  end
end
