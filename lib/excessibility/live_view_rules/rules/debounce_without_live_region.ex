defmodule Excessibility.LiveViewRules.Rules.DebounceWithoutLiveRegion do
  @moduledoc """
  Flags `<input phx-debounce>` when the snapshot has no ARIA live region
  anywhere.

  LiveView search-style inputs with `phx-debounce` push updates silently;
  screen-reader users typing a search term have no idea that results
  appeared or changed. At minimum, the page should contain an
  `aria-live` region (or `role="status" | "alert" | "log"`) somewhere
  the updated results can land.

  ## Detection

  This rule is conservative: it only flags a debounced input when the
  **entire snapshot** has zero ARIA live regions. If any live region
  exists, we assume the app is announcing changes correctly. This
  minimizes false positives at the cost of missing cases where a live
  region exists but isn't where the results actually render.

  ## Fix

      <!-- Bad -->
      <input type="search" name="q" phx-debounce="200" />
      <table><tbody>...results...</tbody></table>

      <!-- Good -->
      <input type="search" name="q" phx-debounce="200" />
      <div aria-live="polite">
        <table><tbody>...results...</tbody></table>
      </div>
  """

  @behaviour Excessibility.LiveViewRules.Rule

  @live_region_selectors [
    "[aria-live]",
    "[role=\"status\"]",
    "[role=\"alert\"]",
    "[role=\"log\"]"
  ]

  @impl true
  def id, do: :debounce_without_live_region

  @impl true
  def default_enabled?, do: true

  @impl true
  def check(tree, _opts) do
    if has_live_region?(tree) do
      []
    else
      tree
      |> Floki.find("input[phx-debounce]")
      |> Enum.map(&build_finding/1)
    end
  end

  # ── Implementation ────────────────────────────────────────────────

  defp has_live_region?(tree) do
    Enum.any?(@live_region_selectors, fn selector ->
      tree |> Floki.find(selector) |> Enum.any?()
    end)
  end

  defp build_finding({tag, attrs, _children} = element) do
    %{
      rule: id(),
      severity: :moderate,
      message:
        "<#{tag}> has phx-debounce but the page has no aria-live region. " <>
          "Screen readers will not announce result updates when the user types.",
      element: element |> Floki.raw_html() |> String.slice(0, 300),
      selector: build_selector(tag, attrs),
      help:
        "Wrap the results container in an element with `aria-live=\"polite\"` " <>
          "or add `role=\"status\"` so assistive tech announces updates.",
      help_url: "https://www.w3.org/WAI/ARIA/apg/practices/live-regions/"
    }
  end

  defp find_attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, v} -> v
      _ -> nil
    end)
  end

  defp build_selector(tag, attrs) do
    case find_attr(attrs, "id") do
      nil -> tag
      id -> "#{tag}##{id}"
    end
  end
end
