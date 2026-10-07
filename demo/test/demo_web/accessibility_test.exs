defmodule DemoWeb.AccessibilityTest do
  @moduledoc """
  Captures an HTML snapshot of each accessibility example. Run the tests to
  generate the snapshots, then check them:

      mix test test/demo_web/accessibility_test.exs
      mix excessibility        # axe-core + LiveView rules over every snapshot

  The `/accessible` snapshot should come back clean; the `/a11y/*` snapshots
  should report the violations documented in each LiveView's moduledoc.
  """
  use DemoWeb.ConnCase
  use Excessibility

  import Phoenix.LiveViewTest

  test "accessible reference page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/accessible")
    html_snapshot(view)
  end

  test "messy form page", %{conn: conn} do
    # on_error: :warn because the page deliberately ships a duplicate id, which
    # LiveViewTest otherwise raises on — that's one of the violations on show.
    {:ok, view, _html} = live(conn, ~p"/a11y/form", on_error: :warn)
    html_snapshot(view)
  end

  test "messy widgets page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/a11y/widgets", on_error: :warn)
    html_snapshot(view)
  end
end
