defmodule Excessibility.DigestCompare do
  @moduledoc """
  Pure, deterministic structural diff of two `excessibility.digest/v1` maps.

  Given a `base` and `head` digest (as produced by `Excessibility.Digest`,
  whether reloaded via `Jason.decode!(..., keys: :atoms)`, decoded with string
  keys, or a raw Elixir map), `diff/2` returns a stable, sorted structural
  delta. It emits **no verdict, no severity beyond advisory, and no merge
  decision** — only the observed structural differences plus measurement-scope
  notes.

  ## The measurement-scope guard

  A signal delta is asserted **only when both digests measured that signal**:

  - Queries/plans are diffed only when both `capture.ecto_configured` are true.
    Otherwise the queries/plans lists stay empty and a `coverage.notes` entry
    explains that one side did not measure queries.
  - Plans are diffed only when both `capture.plan_capture` modes match. A
    difference is scope-noted, never reported as a plan change.
  - Assign deltas are diffed only when the `assign_sizes` enricher ran on both
    sides; other enricher differences are scope-noted.
  - A `schema` mismatch adds a prominent note.

  This keeps compare honest: a change in *what was measured* can never
  masquerade as a real regression.

  ## Key tolerance

  Every field read goes through `get/3`, which tries the atom key then the
  string key, so atom-keyed and string-keyed digests behave identically.

  ## Determinism

  All output lists are sorted by a stable key (`fingerprint`,
  `{view, callback}`, or `name`) and all set math is order-independent, so the
  diff of a given pair is byte-for-byte reproducible regardless of input event
  order.
  """

  @schema "excessibility.digest.compare/v1"
  @assign_enricher "assign_sizes"

  @doc """
  Diff two decoded digest maps. Returns the structural delta described in the
  module docs. Never raises for well-formed digest maps; missing fields fall
  back to empty defaults.
  """
  def diff(base, head) do
    base_scope = scope(base)
    head_scope = scope(head)

    ecto_both? = base_scope.ecto_configured and head_scope.ecto_configured
    plans_comparable? = ecto_both? and base_scope.plan_capture == head_scope.plan_capture

    assigns_both? =
      MapSet.member?(base_scope.enrichers, @assign_enricher) and
        MapSet.member?(head_scope.enrichers, @assign_enricher)

    base_agg = aggregate(base)
    head_agg = aggregate(head)
    shared = shared_keys(base_agg, head_agg)

    %{
      schema: @schema,
      coverage: coverage(base_agg, head_agg, base_scope, head_scope),
      queries: if(ecto_both?, do: query_diffs(base_agg, head_agg, shared), else: []),
      plans: if(plans_comparable?, do: plan_diffs(base_agg, head_agg, shared), else: []),
      assigns: if(assigns_both?, do: assign_diffs(base_agg, head_agg, shared), else: [])
    }
  end

  # --- scope ----------------------------------------------------------------

  defp scope(digest) do
    cap = get(digest, :capture, %{})

    %{
      schema: to_string(get(digest, :schema, "")),
      status: to_string(get(cap, :status, "ok")),
      ecto_configured: get(cap, :ecto_configured, false) == true,
      plan_capture: to_string(get(cap, :plan_capture, "disabled")),
      enrichers: cap |> get(:enrichers_run, []) |> MapSet.new(&to_string/1),
      has_events?: Map.has_key?(digest, :events) or Map.has_key?(digest, "events")
    }
  end

  # Fold events into %{{view, callback} => %{queries, plans, assigns}} where
  # per-fingerprint counts sum, per-fingerprint plans accumulate the full set of
  # distinct structural variants (keyed by plan fingerprint, max row work per
  # node path kept per structure — so neither a later heavier occurrence (#167)
  # nor a non-dominant variant (#173) is discarded), and per-assign
  # term_bytes/cardinality take the max — all order-independent so the aggregate
  # is deterministic.
  defp aggregate(digest) do
    digest
    |> get(:events, [])
    |> Enum.reduce(%{}, fn ev, acc ->
      key = {view_str(get(ev, :view)), to_string(get(ev, :callback))}
      agg = Map.get(acc, key, %{queries: %{}, plans: %{}, assigns: %{}})
      Map.put(acc, key, merge_event(agg, ev))
    end)
  end

  defp merge_event(agg, ev) do
    shapes = ev |> get(:queries, %{}) |> get(:shapes, [])

    {queries, plans} =
      Enum.reduce(shapes, {agg.queries, agg.plans}, fn s, {qacc, pacc} ->
        fp = to_string(get(s, :fingerprint))
        count = get(s, :count, 0) || 0
        qacc = Map.update(qacc, fp, count, &(&1 + count))
        pacc = merge_plan_variants(pacc, fp, s)
        {qacc, pacc}
      end)

    assigns =
      ev
      |> get(:assigns, %{})
      |> get(:shapes, [])
      |> Enum.reduce(agg.assigns, fn a, aacc ->
        name = to_string(get(a, :name))
        term_bytes = get(a, :term_bytes, 0) || 0
        cardinality = get(a, :cardinality)

        Map.update(
          aacc,
          name,
          %{term_bytes: term_bytes, cardinality: cardinality},
          fn ex ->
            %{
              term_bytes: max(ex.term_bytes, term_bytes),
              cardinality: max_cardinality(ex.cardinality, cardinality)
            }
          end
        )
      end)

    %{queries: queries, plans: plans, assigns: assigns}
  end

  defp shared_keys(base_agg, head_agg) do
    MapSet.intersection(
      base_agg |> Map.keys() |> MapSet.new(),
      head_agg |> Map.keys() |> MapSet.new()
    )
  end

  defp query_diffs(base_agg, head_agg, shared) do
    shared
    |> Enum.flat_map(fn {view, callback} = key ->
      base_q = base_agg[key].queries
      head_q = head_agg[key].queries
      base_fps = mapset_keys(base_q)
      head_fps = mapset_keys(head_q)

      added = base_fps |> then(&MapSet.difference(head_fps, &1)) |> Enum.sort()
      removed = base_fps |> MapSet.difference(head_fps) |> Enum.sort()

      count_changed =
        base_fps
        |> MapSet.intersection(head_fps)
        |> Enum.sort()
        |> Enum.filter(fn fp -> Map.fetch!(base_q, fp) != Map.fetch!(head_q, fp) end)
        |> Enum.map(fn fp ->
          %{fingerprint: fp, base_count: base_q[fp], head_count: head_q[fp]}
        end)

      if added == [] and removed == [] and count_changed == [] do
        []
      else
        [
          %{
            view: view,
            callback: callback,
            fingerprints_added: added,
            fingerprints_removed: removed,
            count_changed: count_changed
          }
        ]
      end
    end)
    |> Enum.sort_by(fn %{view: v, callback: c} -> {v, c} end)
  end

  defp plan_diffs(base_agg, head_agg, shared) do
    shared
    |> Enum.flat_map(fn {view, callback} = key ->
      base_plans = base_agg[key].plans
      head_plans = head_agg[key].plans

      base_plans
      |> mapset_keys()
      |> MapSet.intersection(mapset_keys(head_plans))
      |> Enum.sort()
      |> Enum.flat_map(&plan_delta(view, callback, &1, base_plans[&1], head_plans[&1]))
    end)
    |> Enum.sort_by(fn %{view: v, callback: c, fingerprint: fp} -> {v, c, fp} end)
  end

  # One SQL fingerprint carries a *set* of structural plan variants per side
  # (issue #173). A plan change is expressed at the variant level:
  #   * a structure appearing only in head/base is an added/removed variant, and
  #   * a structure present on both sides can still do more work (rows/loops),
  #     reported as a numeric `variant_delta` — the #157 case, where a stable
  #     shape scanning thousands more rows must not read as "no change".
  # Collapsing to a single heaviest representative discarded any non-dominant
  # variant that changed; keeping the whole set is what makes that visible.
  defp plan_delta(view, callback, fingerprint, base_entry, head_entry) do
    base_variants = base_entry.variants
    head_variants = head_entry.variants
    base_fps = mapset_keys(base_variants)
    head_fps = mapset_keys(head_variants)

    added = head_fps |> MapSet.difference(base_fps) |> Enum.sort()
    removed = base_fps |> MapSet.difference(head_fps) |> Enum.sort()

    variant_deltas =
      base_fps
      |> MapSet.intersection(head_fps)
      |> Enum.sort()
      |> Enum.flat_map(&variant_delta(&1, base_variants[&1], head_variants[&1]))

    if added == [] and removed == [] and variant_deltas == [] do
      []
    else
      [
        %{
          view: view,
          callback: callback,
          fingerprint: fingerprint,
          variants_added: added,
          variants_removed: removed,
          variant_deltas: variant_deltas,
          variants_omitted: base_entry.omitted > 0 or head_entry.omitted > 0
        }
      ]
    end
  end

  # A shared variant is the same structure on both sides (same plan fingerprint,
  # so identical node trees in identical depth-first order); numeric root and
  # per-node row deltas carry the magnitude of any change.
  defp variant_delta(plan_fingerprint, base_plan, head_plan) do
    estimated_delta = numeric_delta(base_plan, head_plan, :estimated_rows)
    actual_delta = numeric_delta(base_plan, head_plan, :actual_rows)
    node_deltas = node_deltas(base_plan, head_plan)

    if nonzero?(estimated_delta) or nonzero?(actual_delta) or node_deltas != [] do
      [
        %{
          plan: plan_fingerprint,
          estimated_rows_delta: estimated_delta,
          actual_rows_delta: actual_delta,
          node_deltas: node_deltas
        }
      ]
    else
      []
    end
  end

  # Per-node numeric deltas zip by depth-first position, a stable node identity
  # because the shared variant has an identical node tree on both sides.
  defp node_deltas(base_plan, head_plan) do
    base_nodes = get(base_plan, :node_rows) || []
    head_nodes = get(head_plan, :node_rows) || []

    base_nodes
    |> Enum.zip(head_nodes)
    |> Enum.with_index()
    |> Enum.flat_map(fn {{base_node, head_node}, index} ->
      node_delta(index, base_node, head_node)
    end)
  end

  defp node_delta(index, base_node, head_node) do
    estimated = numeric_delta(base_node, head_node, :estimated_rows)
    actual = numeric_delta(base_node, head_node, :actual_rows)
    touched = numeric_delta(base_node, head_node, :rows_touched)
    loops = numeric_delta(base_node, head_node, :loops)

    if Enum.any?([estimated, actual, touched, loops], &nonzero?/1) do
      [
        %{
          index: index,
          node: get(base_node, :node) || get(head_node, :node),
          relation: get(base_node, :relation) || get(head_node, :relation),
          depth: get(base_node, :depth),
          estimated_rows_delta: estimated,
          actual_rows_delta: actual,
          rows_touched_delta: touched,
          loops_delta: loops
        }
      ]
    else
      []
    end
  end

  defp numeric_delta(base, head, key) do
    base_value = get(base, key)
    head_value = get(head, key)

    if is_number(base_value) and is_number(head_value) do
      head_value - base_value
    end
  end

  defp nonzero?(nil), do: false
  defp nonzero?(0), do: false
  defp nonzero?(value), do: value != 0

  defp assign_diffs(base_agg, head_agg, shared) do
    shared
    |> Enum.flat_map(fn {view, callback} = key ->
      base_a = base_agg[key].assigns
      head_a = head_agg[key].assigns

      base_a
      |> mapset_keys()
      |> MapSet.intersection(mapset_keys(head_a))
      |> Enum.sort()
      |> Enum.flat_map(&assign_delta(view, callback, &1, base_a[&1], head_a[&1]))
    end)
    |> Enum.sort_by(fn %{view: v, callback: c, name: n} -> {v, c, n} end)
  end

  # Exact term_bytes jitter by a byte or two across two otherwise-identical runs
  # is measurement noise, not a collection-growth signal. Suppress a byte-only
  # change (same cardinality) whose magnitude is below the notable threshold;
  # a cardinality change is *never* suppressed, and the exact `delta_bytes`
  # stays on any entry that is reported. Set the threshold to 0 via
  # `config :excessibility, :digest_min_assign_delta_bytes` to restore the old
  # exact-byte behavior.
  @default_min_assign_delta_bytes 64

  defp assign_delta(view, callback, name, base, head) do
    delta = (head.term_bytes || 0) - (base.term_bytes || 0)
    cardinality_unchanged? = base.cardinality == head.cardinality

    if cardinality_unchanged? and abs(delta) < min_assign_delta_bytes() do
      []
    else
      [
        %{
          view: view,
          callback: callback,
          name: name,
          base_term_bytes: base.term_bytes,
          head_term_bytes: head.term_bytes,
          delta_bytes: delta,
          base_cardinality: base.cardinality,
          head_cardinality: head.cardinality
        }
      ]
    end
  end

  defp coverage(base_agg, head_agg, base_scope, head_scope) do
    base_keys = base_agg |> Map.keys() |> MapSet.new()
    head_keys = head_agg |> Map.keys() |> MapSet.new()
    base_views = views(base_agg)
    head_views = views(head_agg)

    %{
      notes: notes(base_scope, head_scope),
      views_added: head_views |> MapSet.difference(base_views) |> Enum.sort(),
      views_removed: base_views |> MapSet.difference(head_views) |> Enum.sort(),
      callbacks_added: head_keys |> MapSet.difference(base_keys) |> Enum.sort(),
      callbacks_removed: base_keys |> MapSet.difference(head_keys) |> Enum.sort()
    }
  end

  defp views(agg) do
    agg |> Map.keys() |> MapSet.new(fn {view, _callback} -> view end)
  end

  # Measurement-scope notes: each describes a *difference in what was measured*,
  # so a scope change is never mistaken for a regression. Sorted + deduped for
  # determinism.
  defp notes(base, head) do
    []
    |> status_note(base, head)
    |> non_digest_note(base, head)
    |> schema_note(base, head)
    |> ecto_note(base, head)
    |> plan_note(base, head)
    |> enricher_note(base, head)
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A failed/partial capture yields empty events, so every delta below is a
  # measurement artifact rather than a real change. Surface that prominently
  # for either side.
  defp status_note(notes, base, head) do
    notes
    |> maybe_status_note(head.status, "head")
    |> maybe_status_note(base.status, "base")
  end

  defp maybe_status_note(notes, "ok", _side), do: notes

  defp maybe_status_note(notes, status, side) do
    [
      "#{side} capture did not complete (status: #{status}) — coverage/query deltas below are unreliable"
      | notes
    ]
  end

  # Valid JSON that is not a digest (no events on either side) produces no
  # meaningful structural deltas; flag it so the empty result is not read as
  # "no changes".
  defp non_digest_note(notes, base, head) do
    if not base.has_events? and not head.has_events? do
      ["input does not look like an excessibility digest (no events)" | notes]
    else
      notes
    end
  end

  defp schema_note(notes, base, head) do
    if base.schema == head.schema do
      notes
    else
      ["schema mismatch (base: #{base.schema}, head: #{head.schema})" | notes]
    end
  end

  defp ecto_note(notes, base, head) do
    cond do
      base.ecto_configured == head.ecto_configured ->
        notes

      not base.ecto_configured ->
        ["base did not measure queries (ecto not configured)" | notes]

      true ->
        ["head did not measure queries (ecto not configured)" | notes]
    end
  end

  defp plan_note(notes, base, head) do
    if base.ecto_configured and head.ecto_configured and base.plan_capture != head.plan_capture do
      ["plan capture differs (base: #{base.plan_capture}, head: #{head.plan_capture})" | notes]
    else
      notes
    end
  end

  defp enricher_note(notes, base, head) do
    base_only = base.enrichers |> MapSet.difference(head.enrichers) |> Enum.sort()
    head_only = head.enrichers |> MapSet.difference(base.enrichers) |> Enum.sort()

    if base_only == [] and head_only == [] do
      notes
    else
      [
        "enrichers differ (base only: #{fmt_list(base_only)}; head only: #{fmt_list(head_only)})"
        | notes
      ]
    end
  end

  defp fmt_list([]), do: "none"
  defp fmt_list(list), do: Enum.join(list, ", ")

  # Fold one shape's plan variants into the {sql_fp => %{variants, omitted}}
  # accumulator. Accepts both the current `:plans` list and a legacy single
  # `:plan` (wrapped), so reloaded pre-#173 digests still compare. Variants key
  # by plan fingerprint; occurrences of the same structure across events keep the
  # max comparable row work per node position (a later, heavier occurrence is not
  # discarded — issue #167), independent of event order.
  defp merge_plan_variants(pacc, fp, shape) do
    variants = plan_variants_of(shape)
    omitted = get(shape, :variants_omitted, 0) || 0

    if variants == [] and omitted == 0 do
      pacc
    else
      entry = Map.get(pacc, fp, %{variants: %{}, omitted: 0})

      merged =
        Enum.reduce(variants, entry.variants, fn plan, vacc ->
          pfp = to_string(get(plan, :fingerprint))
          Map.update(vacc, pfp, plan, &merge_plan(&1, plan))
        end)

      Map.put(pacc, fp, %{variants: merged, omitted: max(entry.omitted, omitted)})
    end
  end

  defp plan_variants_of(shape) do
    case get(shape, :plans) do
      plans when is_list(plans) ->
        plans

      _ ->
        case get(shape, :plan) do
          nil -> []
          plan -> [plan]
        end
    end
  end

  # Two instances of the same structure (same plan fingerprint): keep the max
  # comparable row work per node position, so a variant's reported magnitude is
  # its worst observed instance.
  defp merge_plan(existing, candidate) do
    %{
      fingerprint: get(existing, :fingerprint),
      estimated_rows: max_num(get(existing, :estimated_rows), get(candidate, :estimated_rows)),
      actual_rows: max_num(get(existing, :actual_rows), get(candidate, :actual_rows)),
      loops: max_num(get(existing, :loops), get(candidate, :loops)),
      node_rows: merge_node_rows(get(existing, :node_rows) || [], get(candidate, :node_rows) || [])
    }
  end

  # Zip by position (stable node identity under a shared structural fingerprint)
  # and keep the max comparable row work per node. Tolerant of length drift.
  defp merge_node_rows(existing, candidate) do
    count = max(length(existing), length(candidate))

    Enum.map(0..(count - 1)//1, fn i ->
      merge_node(Enum.at(existing, i), Enum.at(candidate, i))
    end)
  end

  defp merge_node(nil, node), do: node
  defp merge_node(node, nil), do: node

  defp merge_node(a, b) do
    %{
      node: get(a, :node) || get(b, :node),
      relation: get(a, :relation) || get(b, :relation),
      depth: get(a, :depth),
      estimated_rows: max_num(get(a, :estimated_rows), get(b, :estimated_rows)),
      actual_rows: max_num(get(a, :actual_rows), get(b, :actual_rows)),
      loops: max_num(get(a, :loops), get(b, :loops)),
      rows_touched: max_num(get(a, :rows_touched), get(b, :rows_touched)),
      estimate_error: max_num(get(a, :estimate_error), get(b, :estimate_error))
    }
  end

  defp max_num(a, b) do
    cond do
      is_number(a) and is_number(b) -> max(a, b)
      is_number(a) -> a
      is_number(b) -> b
      true -> nil
    end
  end

  defp min_assign_delta_bytes do
    Application.get_env(:excessibility, :digest_min_assign_delta_bytes, @default_min_assign_delta_bytes)
  end

  defp max_cardinality(nil, other), do: other
  defp max_cardinality(other, nil), do: other
  defp max_cardinality(a, b), do: max(a, b)

  defp mapset_keys(map), do: map |> Map.keys() |> MapSet.new()

  defp view_str(nil), do: nil
  defp view_str(view), do: view |> to_string() |> String.replace_prefix("Elixir.", "")
  defp get(map, key, default \\ nil)

  defp get(map, key, default) when is_map(map) and is_atom(key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key), default)
    end
  end

  defp get(_map, _key, default), do: default
end
