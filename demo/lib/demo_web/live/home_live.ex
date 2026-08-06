defmodule DemoWeb.HomeLive do
  @moduledoc """
  Landing page. Groups the demo into the two things Excessibility catches:
  accessibility issues (static snapshots → axe-core + LiveView rules) and
  performance issues (a telemetry timeline → behavioral analyzers). This page
  is itself accessible — it's part of the happy path.
  """
  use DemoWeb, :live_view

  @a11y [
    {"Accessible reference", "/accessible", "The happy path — a clean page a review comes back green on."},
    {"Messy form", "/a11y/form", "Common form failures: missing labels, no accessible names, duplicate ids, a phx-debounce field with no live region."},
    {"Messy widgets", "/a11y/widgets", "LiveView-specific rules: phx-click on a div, a toggle with no aria-pressed, content revealed with no announcement."}
  ]

  @perf [
    {"N+1 queries", "/perf/n-plus-one", "One query per row in a single handle_event — caught by ecto_query_analysis."},
    {"Memory leak", "/perf/memory", "An assign that grows unbounded every click — caught by memory + data_growth."},
    {"Render thrash", "/perf/renders", "Events that re-assign identical state — caught by handle_event_noop."},
    {"Message flood", "/perf/messages", "A burst of handle_info messages — caught by message_flooding (needs the on_mount hook)."}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, a11y: @a11y, perf: @perf)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page">
      <h1>Excessibility demo</h1>
      <p>
        Each page below is a deliberate example. Capture snapshots and run
        <code>mix excessibility</code> for the accessibility pages, or
        <code>mix excessibility.debug</code> for the performance pages.
      </p>

      <section aria-labelledby="a11y-heading">
        <h2 id="a11y-heading">Accessibility examples</h2>
        <ul>
          <li :for={{title, path, desc} <- @a11y}>
            <.link navigate={path}>{title}</.link> — {desc}
          </li>
        </ul>
      </section>

      <section aria-labelledby="perf-heading">
        <h2 id="perf-heading">Performance examples</h2>
        <ul>
          <li :for={{title, path, desc} <- @perf}>
            <.link navigate={path}>{title}</.link> — {desc}
          </li>
        </ul>
      </section>
    </main>
    """
  end
end
