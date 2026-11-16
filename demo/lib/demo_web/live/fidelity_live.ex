defmodule DemoWeb.FidelityLive do
  @moduledoc """
  Markup that a snapshot has to reproduce exactly to render like the app: a
  flash with an inline link, inline elements against punctuation, whitespace
  between inline-blocks, preformatted text, an image alone on its line,
  entities and non-ASCII text. `DemoWeb.SnapshotFidelityTest` renders this page
  and its snapshot side by side and compares them.
  """
  use DemoWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.flash kind={:info} id="flash-saved">
        Draft saved. <.link navigate={~p"/"}>Undo</.link>.
      </.flash>

      <h1>Snapshot fidelity</h1>

      <p>
        A <a href="/accessible">link</a>, then <strong>bold</strong><em>italic</em>
        with no space, <code>code</code>; and a&nbsp;non-breaking space.
      </p>

      <p>Café, naïve, ✓ — and &lt;escaped&gt; &amp; “quoted”.</p>

      <p>
        <button type="button" class="btn">Spaced</button>
        <button type="button" class="btn">buttons</button><button type="button" class="btn">Touching</button>
      </p>

      <p><img src="/images/logo.svg" alt="Logo alone on its line" width="40" height="40" /></p>

      <pre>  indented
        more indented</pre>

      <pre>

    after a blank first line</pre>

      <label for="notes">Notes</label>
      <textarea id="notes" name="notes" rows="3">  leading spaces
    second line</textarea>

      <table>
        <caption>Totals</caption>
        <tr>
          <th scope="row">Orders</th>
          <td>12</td>
        </tr>
      </table>
    </Layouts.app>
    """
  end
end
