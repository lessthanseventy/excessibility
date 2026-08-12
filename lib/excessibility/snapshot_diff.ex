defmodule Excessibility.SnapshotDiff do
  @moduledoc """
  Cross-snapshot diffing: compare two HTML snapshots of the same view and
  report the regions whose rendered content changed.

  This is a capability no single-snapshot tool (axe-core included) can
  provide: by comparing a *before* and *after* of the same template it can
  detect that visible content changed. The first consumer is the
  accessibility check in `live_region_findings/3` — LiveView patches the
  DOM without a page load, so content that updates outside an `aria-live`
  region (or `role="alert"|"status"|"log"`, or `<output>`) is never
  announced to screen-reader users (WCAG 2.1 SC 4.1.3, Status Messages).

  `diff/3` itself is content-agnostic and returns the structural delta, so
  it doubles as a general-purpose semantic DOM diff for other callers.

  ## Diff strategy

  Both snapshots are parsed and walked in parallel from `<body>` down,
  matching element children positionally by tag. The change is localized
  to the **deepest element whose subtree text differs but whose children
  still line up** — i.e. the smallest stable container that owns the
  change. When the child structure itself diverges (rows added/removed,
  tags differ), that parent is reported as the changed region. Text is
  whitespace-normalized, so reflow/indentation differences are ignored.
  """

  alias Excessibility.LiveViewRules.Rule

  @live_roles ~w(alert status log)
  @input_tags ~w(textarea input select)

  # Text-ratio fallback for classifying a *dead-render* navigation (issue
  # #193, Case A) when neither snapshot has a LiveView root to key on. It is
  # deliberately NOT applied to a same-view LiveView patch — there, identity
  # (a stable root id) already proves the change is in-place, so a small
  # fully-replaced region (a toast, a counter) stays a real status message.
  #
  # A region qualifies as navigation-scale only when it is (a) substantial in
  # absolute size — a short status region can never be a "page" — AND (b) the
  # bulk of the document (`coverage`) AND (c) almost entirely new text
  # (`overlap`). The size floor is what prevents suppressing a small
  # region-dominated status update in a non-rooted fragment.
  @nav_min_chars 64
  @nav_coverage_threshold 0.5
  @nav_overlap_threshold 0.2

  @typedoc "A single changed region produced by `diff/3`."
  @type region :: %{
          change: :changed,
          selector: String.t(),
          tag: String.t(),
          old_text: String.t(),
          new_text: String.t(),
          announced: boolean(),
          user_input: boolean(),
          size: non_neg_integer(),
          coverage: float(),
          overlap: float(),
          element: String.t()
        }

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Diff two HTML snapshots and return the list of changed regions.

  Each region is the deepest stable container whose normalized text
  content differs between `old_html` and `new_html`. Returns `[]` when the
  documents are content-equivalent (whitespace aside) or either fails to
  parse.
  """
  @spec diff(String.t(), String.t(), keyword()) :: [region()]
  def diff(old_html, new_html, _opts \\ []) when is_binary(old_html) and is_binary(new_html) do
    with {:ok, old_tree} <- Floki.parse_document(old_html),
         {:ok, new_tree} <- Floki.parse_document(new_html) do
      old_root = root_node(old_tree)
      new_root = root_node(new_tree)
      doc_len = max(String.length(text(old_root)), String.length(text(new_root)))

      old_root
      |> regions(new_root, [])
      |> Enum.map(&put_coverage(&1, doc_len))
    else
      _ -> []
    end
  end

  # Coverage is the region's share of the whole document's text; it can only
  # be computed once the document length is known, so `region/3` records the
  # region's own `size` and `diff/3` divides here.
  defp put_coverage(region, doc_len) when doc_len > 0, do: %{region | coverage: region.size / doc_len}

  defp put_coverage(region, _doc_len), do: %{region | coverage: 0.0}

  @doc """
  Return accessibility findings for content that changed outside any live
  region, in the `t:Excessibility.LiveViewRules.Rule.finding/0` shape.

  A change is considered *announced* (and therefore not flagged) when the
  changed region or any of its ancestors is an `aria-live` region (a value
  other than `"off"`), carries `role="alert"|"status"|"log"`, or is an
  `<output>` element.
  """
  @spec live_region_findings(String.t(), String.t(), keyword()) :: [Rule.finding()]
  def live_region_findings(old_html, new_html, opts \\ []) do
    # When both snapshots are the same LiveView instance (same root id), the
    # change is an in-place patch by definition, so the navigation-scale text
    # heuristic must not run — identity already settled it. It only applies
    # to the indeterminate case (controller/static pages with no root).
    nav_heuristic? = not same_rooted_view?(old_html, new_html)

    old_html
    |> diff(new_html, opts)
    |> Enum.reject(&suppress?(&1, nav_heuristic?))
    |> Enum.map(&build_finding/1)
  end

  # A changed region is not a status message — and so must not be flagged —
  # when it is already announced (aria-live/role/output), when the user
  # authored it themselves (a form control they are typing into; issue #193
  # Case B), or, for non-LiveView pages only, when it is a full-page
  # navigation rather than an in-place patch (issue #193 Case A).
  defp suppress?(region, nav_heuristic?) do
    region.announced or region.user_input or
      (nav_heuristic? and navigation_scale?(region))
  end

  defp navigation_scale?(%{size: size, coverage: coverage, overlap: overlap}) do
    size >= @nav_min_chars and coverage >= @nav_coverage_threshold and
      overlap <= @nav_overlap_threshold
  end

  @doc """
  Run `live_region_findings/3` over each consecutive pair in a list of
  snapshots captured for the same test, and concatenate the findings.

  Pairs that straddle a full-page navigation are skipped: when both
  snapshots carry a LiveView root id and the ids differ, they are separate
  views (a fresh mount, not an in-place patch) and the live-region rule
  does not apply. Pairs with indeterminate identity (controller/static
  snapshots) are diffed as usual.
  """
  @spec scan_sequence([String.t()], keyword()) :: [Rule.finding()]
  def scan_sequence(snapshots, opts \\ []) when is_list(snapshots) do
    snapshots
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [old, new] -> pair_findings(old, new, opts) end)
  end

  @doc """
  Diff snapshot *files* on disk, grouped by the test that produced them.

  Auto-captured snapshots embed a `Test:`/`Sequence:` metadata comment;
  this groups files by test, orders them by sequence, and diffs each
  consecutive pair. Returns `{file, finding}` tuples where `file` is the
  later snapshot of the pair the finding came from.

  Snapshots without that metadata (the default `Module_line.html` naming
  carries no reliable test boundary) are skipped, so this is inert unless
  capture metadata is present. Consecutive pairs that straddle a full-page
  navigation are skipped the same way as in `scan_sequence/2`.
  """
  @spec scan_files([Path.t()], keyword()) :: [{Path.t(), Rule.finding()}]
  def scan_files(paths, opts \\ []) when is_list(paths) do
    paths
    |> Enum.map(&read_with_meta/1)
    |> Enum.filter(fn {_path, _html, meta} -> meta != nil end)
    |> Enum.group_by(fn {_path, _html, meta} -> meta.test end)
    |> Enum.flat_map(fn {_test, entries} -> diff_group(entries, opts) end)
  end

  defp read_with_meta(path) do
    case File.read(path) do
      {:ok, html} -> {path, html, parse_meta(html)}
      {:error, _} -> {path, "", nil}
    end
  end

  defp parse_meta(html) do
    with [_, test] <- Regex.run(~r/Test:\s*(.+)/, html),
         [_, sequence] <- Regex.run(~r/Sequence:\s*(\d+)/, html) do
      %{test: String.trim(test), sequence: String.to_integer(sequence)}
    else
      _ -> nil
    end
  end

  defp diff_group(entries, opts) do
    entries
    |> Enum.sort_by(fn {_path, _html, meta} -> meta.sequence end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn [{_p1, old, _m1}, {p2, new, _m2}] ->
      old |> pair_findings(new, opts) |> Enum.map(&{p2, &1})
    end)
  end

  # Cross-snapshot findings for a single consecutive pair, guarded against
  # full-page navigations. Journey-style tests snapshot several *different*
  # views in one test; those pairs are separate pages, not an in-place
  # LiveView patch, so the live-region rule (WCAG 4.1.3, which is about DOM
  # patches without a page load) does not apply — flagging them would be a
  # false positive whose only "fix" (wrapping layout in aria-live) re-reads
  # the whole page on every navigation.
  defp pair_findings(old_html, new_html, opts) do
    if navigation?(old_html, new_html),
      do: [],
      else: live_region_findings(old_html, new_html, opts)
  end

  # A pair is a navigation, on value-free structural evidence, when:
  #   * both sides carry a LiveView root id and the ids differ — a fresh
  #     mount, not a patch; or
  #   * exactly one side carries a LiveView root — a LiveView cannot patch
  #     into a dead controller render, so presence-differs is a page change.
  # Neither-rooted pairs (controller/static/plain fragments) are indeterminate
  # here; that case is handled downstream by the size/coverage/overlap
  # heuristic in `navigation_scale?/1`, so nothing is silently dropped.
  defp navigation?(old_html, new_html) do
    case {view_identity(old_html), view_identity(new_html)} do
      {nil, nil} -> false
      {old_id, new_id} when is_binary(old_id) and is_binary(new_id) -> old_id != new_id
      _ -> true
    end
  end

  # True only when both snapshots are provably the same LiveView instance
  # (same root id) — i.e. any content change between them is an in-place
  # patch, where the navigation-scale heuristic must stand down.
  defp same_rooted_view?(old_html, new_html) do
    case {view_identity(old_html), view_identity(new_html)} do
      {old_id, new_id} when is_binary(old_id) and is_binary(new_id) -> old_id == new_id
      _ -> false
    end
  end

  # A LiveView's root element carries a per-mount, patch-stable identity: a
  # fresh `live/2` mount gets a new `id`, an in-place patch keeps it. Prefer
  # the main root, fall back to any connected root, then to the root-id a
  # nested view points back to. Returns nil when no LiveView root is present
  # (controller/static snapshots), i.e. identity is indeterminate.
  defp view_identity(html) do
    case Floki.parse_document(html) do
      {:ok, tree} -> root_id(tree)
      _ -> nil
    end
  end

  defp root_id(tree) do
    first_attr(tree, "[data-phx-main]", "id") ||
      first_attr(tree, "[data-phx-session]", "id") ||
      first_attr(tree, "[data-phx-root-id]", "data-phx-root-id")
  end

  defp first_attr(tree, selector, attr) do
    tree
    |> Floki.attribute(selector, attr)
    |> List.first()
  end

  # ── Diff walk ──────────────────────────────────────────────────────

  defp regions(old_node, new_node, ancestors) do
    if text(old_node) == text(new_node),
      do: [],
      else: diff_changed(old_node, new_node, ancestors)
  end

  defp diff_changed(old_node, new_node, ancestors) do
    old_children = element_children(old_node)
    new_children = element_children(new_node)

    if old_children != [] and matchable?(old_children, new_children),
      do: localize(old_node, new_node, ancestors, old_children, new_children),
      else: [region(old_node, new_node, ancestors)]
  end

  # Recurse into the matched children; if none of them changed, the change
  # lives in this node's own text nodes, so report this node itself.
  defp localize(old_node, new_node, ancestors, old_children, new_children) do
    child_ancestors = [new_node | ancestors]

    deeper =
      old_children
      |> Enum.zip(new_children)
      |> Enum.flat_map(fn {o, n} -> regions(o, n, child_ancestors) end)

    if deeper == [], do: [region(old_node, new_node, ancestors)], else: deeper
  end

  defp region(old_node, new_node, ancestors) do
    {tag, _attrs, _children} = new_node
    old_full = text(old_node)
    new_full = text(new_node)
    lineage = [new_node | ancestors]

    %{
      change: :changed,
      selector: selector(new_node),
      tag: tag,
      old_text: String.slice(old_full, 0, 300),
      new_text: String.slice(new_full, 0, 300),
      announced: Enum.any?(lineage, &live_region?/1),
      user_input: Enum.any?(lineage, &user_input?/1),
      size: max(String.length(old_full), String.length(new_full)),
      # `coverage` is filled in by `diff/3` once the document length is known.
      coverage: 0.0,
      overlap: token_overlap(old_full, new_full),
      element: new_node |> Floki.raw_html() |> String.slice(0, 300)
    }
  end

  # ── Findings ───────────────────────────────────────────────────────

  defp build_finding(region) do
    %{
      rule: :content_change_without_live_region,
      severity: :moderate,
      message:
        "<#{region.tag}> content changed between snapshots but is not inside an " <>
          "aria-live region. Screen readers will not announce the update.",
      element: region.element,
      selector: region.selector,
      help:
        ~s|Wrap dynamically-updated content in a container with aria-live="polite" | <>
          ~s|(or role="status"/"alert"/"log", or use <output>) so assistive | <>
          ~s|technology announces changes made via LiveView patches.|,
      help_url: "https://www.w3.org/WAI/WCAG21/Understanding/status-messages.html"
    }
  end

  # ── HTML helpers ───────────────────────────────────────────────────

  defp root_node(tree) do
    case Floki.find(tree, "body") do
      [body | _] -> body
      [] -> {"#root", [], tree}
    end
  end

  defp text(node) do
    # `sep: " "` puts a space between adjacent text nodes so element
    # boundaries (e.g. `<td>A</td><td>B</td>`) become token boundaries, which
    # keeps token-overlap meaningful. The separator collapses under the
    # whitespace normalization below; this slightly increases diff sensitivity
    # at element boundaries (biasing toward flagging, never toward suppressing).
    node
    |> Floki.text(sep: " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp element_children({_tag, _attrs, children}), do: Enum.filter(children, &element?/1)
  defp element_children(_), do: []

  defp element?({tag, _attrs, _children}) when is_binary(tag), do: true
  defp element?(_), do: false

  # Children "line up" when there is the same number of element children
  # and they are the same tags in the same order.
  defp matchable?(old_children, new_children) do
    length(old_children) == length(new_children) and
      old_children
      |> Enum.zip(new_children)
      |> Enum.all?(fn {{ot, _, _}, {nt, _, _}} -> ot == nt end)
  end

  defp live_region?({tag, attrs, _children}) do
    tag == "output" or live_role?(attrs) or live_aria?(attrs)
  end

  defp live_region?(_), do: false

  # A form control (or contenteditable region) holds content the user typed,
  # which assistive tech already echoes — it is never a status message.
  defp user_input?({tag, attrs, _children}) do
    tag in @input_tags or contenteditable?(attrs)
  end

  defp user_input?(_), do: false

  defp contenteditable?(attrs) do
    case find_attr(attrs, "contenteditable") do
      nil -> false
      value -> String.downcase(value) != "false"
    end
  end

  # Jaccard overlap of the two texts' word sets, in [0.0, 1.0]. 1.0 when both
  # are empty (no change to measure). Used to tell a wholesale replacement
  # (near 0.0) from a mostly-stable update (near 1.0).
  defp token_overlap(old_text, new_text) do
    old_tokens = tokenize(old_text)
    new_tokens = tokenize(new_text)
    union = old_tokens |> MapSet.union(new_tokens) |> MapSet.size()

    if union == 0 do
      1.0
    else
      intersection = old_tokens |> MapSet.intersection(new_tokens) |> MapSet.size()
      intersection / union
    end
  end

  defp tokenize(text) do
    text |> String.downcase() |> String.split(~r/\s+/, trim: true) |> MapSet.new()
  end

  defp live_role?(attrs) do
    case find_attr(attrs, "role") do
      nil -> false
      role -> String.downcase(role) in @live_roles
    end
  end

  defp live_aria?(attrs) do
    case find_attr(attrs, "aria-live") do
      nil -> false
      value -> String.downcase(value) not in ["", "off"]
    end
  end

  defp selector({tag, attrs, _children}) do
    cond do
      id = find_attr(attrs, "id") -> "#{tag}##{id}"
      class = attrs |> find_attr("class") |> first_class() -> "#{tag}.#{class}"
      true -> tag
    end
  end

  defp first_class(nil), do: nil

  defp first_class(class_str) do
    class_str |> String.split(~r/\s+/, trim: true) |> List.first()
  end

  defp find_attr(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, v} -> v
      _ -> nil
    end)
  end
end
