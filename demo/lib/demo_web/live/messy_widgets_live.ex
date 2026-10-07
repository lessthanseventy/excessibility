defmodule DemoWeb.MessyWidgetsLive do
  @moduledoc """
  Accessibility errors — interactive widgets. A "dashboard" of custom controls
  that trips the LiveView-specific rules axe-core can't see, plus common markup
  failures, all on one page.

  What a review of this page surfaces:

    * LiveView rules — `phx_click_on_non_interactive` (a `<div phx-click>` acting
      as a button), `toggle_missing_aria_state` (JS toggles with no
      `aria-expanded`), `reveal_without_announcement` (a hidden banner shown via
      `JS.show` with no `aria-live`), and `click_away_without_escape` (a
      `phx-click-away` menu with no Escape key).
    * axe/WCAG — an `<a>` with no text, a positive `tabindex`, a heading-order
      jump (`<h1>` → `<h4>`), and a data `<table>` with no header cells.
  """
  use DemoWeb, :live_view

  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :note, "")}

  @impl true
  def handle_event("open_details", _p, socket), do: {:noreply, assign(socket, :note, "Loading…")}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page">
      <h1>Dashboard</h1>

      <!-- phx-click on a non-interactive element (rule: phx_click_on_non_interactive) -->
      <div phx-click="open_details" class="card">Show account details</div>
      <p>{@note}</p>

      <!-- JS toggle with no aria-expanded (rule: toggle_missing_aria_state) -->
      <button type="button" phx-click={JS.toggle(to: "#help")}>Help</button>
      <div id="help" class="hidden">
        <p>Manage your plan and billing here.</p>
      </div>

      <!-- Hidden banner revealed via JS.show with no aria-live (rule:
           reveal_without_announcement; the trigger also has no aria-expanded) -->
      <button type="button" phx-click={JS.show(to: "#promo")}>See today's offer</button>
      <div id="promo" class="hidden">
        <p>50% off Pro — today only.</p>
      </div>

      <!-- Menu dismissed on click-away with no Escape key (rule:
           click_away_without_escape) -->
      <button type="button" phx-click={JS.toggle(to: "#menu")}>Options</button>
      <ul id="menu" class="hidden" phx-click-away={JS.hide(to: "#menu")}>
        <li><a href="/perf/memory">Memory example</a></li>
        <!-- Link with no discernible text (axe: link-name) -->
        <li><a href="/perf/renders"></a></li>
      </ul>

      <!-- Positive tabindex (axe: tabindex) -->
      <button type="button" tabindex="3">Buy credits</button>

      <!-- Heading level jump h1 -> h4 (axe: heading-order) -->
      <h4>Recent activity</h4>

      <!-- Data table with no header cells (axe) -->
      <table>
        <tr>
          <td>2026-05-01</td>
          <td>Upgraded to Pro</td>
        </tr>
        <tr>
          <td>2026-04-15</td>
          <td>Signed up</td>
        </tr>
      </table>
    </main>
    """
  end
end
