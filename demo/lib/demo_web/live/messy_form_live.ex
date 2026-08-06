defmodule DemoWeb.MessyFormLive do
  @moduledoc """
  Accessibility errors — forms. A realistic "account settings" form that packs
  many of the most common form a11y failures into one page (not one per rule).

  What a review of this page surfaces:

    * axe/WCAG — inputs with no `<label>` (placeholder-only), a `<select>` with
      no accessible name, an `<img>` with no `alt`, low-contrast help text, a
      duplicate `id`, an icon `<button>` with no discernible text, and radio
      buttons with no `<fieldset>`/`<legend>`.
    * LiveView rules — `hidden_form_control_without_aria` (a `phx`-driven hidden
      input) and `debounce_without_live_region` (a `phx-debounce` field whose
      validation text has no `aria-live`).
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :username_taken?, false)}
  end

  @impl true
  def handle_event("check", %{"username" => name}, socket) do
    {:noreply, assign(socket, :username_taken?, name in ~w(admin root demo))}
  end

  def handle_event("save", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <main class="page">
      <h1>Account settings</h1>

      <form phx-submit="save">
        <!-- No <label>: placeholder is not a label (axe: label) -->
        <input name="email" type="email" placeholder="Email address" />

        <!-- phx-debounce validation with no aria-live region (LiveView rule) -->
        <input name="username" type="text" placeholder="Username" phx-keyup="check" phx-debounce="300" />
        <p :if={@username_taken?} style="color: #b3b3b3">That username is taken.</p>

        <!-- <select> with no accessible name (axe: select-name) -->
        <select name="timezone">
          <option>UTC</option>
          <option>US/Eastern</option>
        </select>

        <!-- Radios with no fieldset/legend grouping (axe) -->
        <p>Plan</p>
        <input id="plan-free" name="plan" type="radio" value="free" />
        <input id="plan-pro" name="plan" type="radio" value="pro" />

        <!-- Duplicate id (axe: duplicate-id) -->
        <input id="plan-free" name="referral" type="text" placeholder="Referral code" />

        <!-- Avatar preview with no alt (axe: image-alt) -->
        <img src="/images/logo.svg" width="48" height="48" />

        <!-- Custom "chip" backed by a visually-hidden checkbox whose label
             carries no aria-checked/role (LiveView: hidden_form_control_without_aria) -->
        <label class="chip">
          <input type="checkbox" class="hidden" name="notify" value="1" />
          Email me updates
        </label>

        <!-- Icon-only submit with no accessible name (axe: button-name) -->
        <button type="submit">💾</button>
      </form>
    </main>
    """
  end
end
