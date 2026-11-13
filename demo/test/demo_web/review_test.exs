defmodule DemoWeb.ReviewTest do
  @moduledoc """
  Snapshots the pages whose data differs on every run. `mix review.same_commit`
  renders them twice and reviews the second render against the first.
  """
  use DemoWeb.ConnCase
  use Excessibility

  import Phoenix.LiveViewTest

  test "orders page with per-run data", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/review/orders")
    html_snapshot(view)
  end

  test "broken orders page with per-run ids", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/review/messy-orders")
    html_snapshot(view)
  end
end
