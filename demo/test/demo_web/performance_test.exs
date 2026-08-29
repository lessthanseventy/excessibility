defmodule DemoWeb.PerformanceTest do
  @moduledoc """
  Drives each performance example so a telemetry timeline is captured, then the
  behavioral analyzers can report on it:

      mix excessibility.debug test/demo_web/performance_test.exs:LINE

  (one test at a time keeps each timeline focused). `message_flooding` is opt-in
  — enable it with `--analyze=message_flooding` — and relies on the
  `Excessibility.TelemetryCapture` on_mount hook wired in the router.
  """
  use DemoWeb.ConnCase
  use Excessibility

  import Phoenix.LiveViewTest

  @tag generate_timeline: true
  test "N+1 queries in a single handle_event", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/perf/n-plus-one")

    render_click(view, "load", %{})

    html_snapshot(view)
  end

  @tag generate_timeline: true
  test "unbounded memory growth", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/perf/memory")

    for _ <- 1..6, do: render_click(view, "grow", %{})

    html_snapshot(view)
  end

  @tag generate_timeline: true
  test "render thrash from no-op events", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/perf/renders")

    for _ <- 1..8, do: render_click(view, "tick", %{})

    html_snapshot(view)
  end

  @tag generate_timeline: true
  test "handle_info message flood", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/perf/messages")

    # render/1 drains the mailbox, so all 30 :tick messages are processed
    # (and captured) by the time it returns.
    assert render(view) =~ "Ticks: 30"

    html_snapshot(view)
  end
end
