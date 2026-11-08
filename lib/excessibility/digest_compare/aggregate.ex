defmodule Excessibility.DigestCompare.Aggregate do
  @moduledoc """
  Folds a digest's events into one order-independent aggregate per
  `{view, callback}` for `Excessibility.DigestCompare` to diff.
  """

  alias Excessibility.DigestCompare

  # Fold events into %{{view, callback} => %{queries, plans, assigns}} where
  # per-fingerprint counts sum, per-fingerprint plans accumulate the full set of
  # distinct structural variants (keyed by plan fingerprint, max row work per
  # node path kept per structure — so neither a later heavier occurrence
  # nor a non-dominant variant is discarded), and per-assign
  # term_bytes/cardinality take the max — all order-independent so the aggregate
  # is deterministic.
  def aggregate(digest) do
    digest
    |> DigestCompare.get(:events, [])
    |> Enum.reduce(%{}, fn ev, acc ->
      key = {view_str(DigestCompare.get(ev, :view)), to_string(DigestCompare.get(ev, :callback))}
      agg = Map.get(acc, key, %{queries: %{}, plans: %{}, assigns: %{}})
      Map.put(acc, key, merge_event(agg, ev))
    end)
  end

  defp merge_event(agg, ev) do
    shapes = ev |> DigestCompare.get(:queries, %{}) |> DigestCompare.get(:shapes, [])

    {queries, plans} =
      Enum.reduce(shapes, {agg.queries, agg.plans}, fn s, {qacc, pacc} ->
        fp = to_string(DigestCompare.get(s, :fingerprint))
        count = DigestCompare.get(s, :count, 0) || 0
        qacc = Map.update(qacc, fp, count, &(&1 + count))
        pacc = merge_plan_variants(pacc, fp, s)
        {qacc, pacc}
      end)

    assigns =
      ev
      |> DigestCompare.get(:assigns, %{})
      |> DigestCompare.get(:shapes, [])
      |> Enum.reduce(agg.assigns, fn a, aacc ->
        name = to_string(DigestCompare.get(a, :name))
        term_bytes = DigestCompare.get(a, :term_bytes, 0) || 0
        cardinality = DigestCompare.get(a, :cardinality)

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

  # Fold one shape's plan variants into the {sql_fp => %{variants, omitted}}
  # accumulator. Accepts both the current `:plans` list and a legacy single
  # `:plan` (wrapped), so reloaded older digests still compare. Variants key
  # by plan fingerprint; occurrences of the same structure across events keep the
  # max comparable row work per node position (a later, heavier occurrence is not
  # discarded), independent of event order.
  defp merge_plan_variants(pacc, fp, shape) do
    variants = plan_variants_of(shape)
    omitted = DigestCompare.get(shape, :variants_omitted, 0) || 0

    if variants == [] and omitted == 0 do
      pacc
    else
      entry = Map.get(pacc, fp, %{variants: %{}, omitted: 0})

      merged =
        Enum.reduce(variants, entry.variants, fn plan, vacc ->
          pfp = to_string(DigestCompare.get(plan, :fingerprint))
          Map.update(vacc, pfp, plan, &merge_plan(&1, plan))
        end)

      Map.put(pacc, fp, %{variants: merged, omitted: max(entry.omitted, omitted)})
    end
  end

  defp plan_variants_of(shape) do
    case DigestCompare.get(shape, :plans) do
      plans when is_list(plans) ->
        plans

      _ ->
        case DigestCompare.get(shape, :plan) do
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
      fingerprint: DigestCompare.get(existing, :fingerprint),
      estimated_rows:
        max_num(DigestCompare.get(existing, :estimated_rows), DigestCompare.get(candidate, :estimated_rows)),
      actual_rows: max_num(DigestCompare.get(existing, :actual_rows), DigestCompare.get(candidate, :actual_rows)),
      loops: max_num(DigestCompare.get(existing, :loops), DigestCompare.get(candidate, :loops)),
      node_rows:
        merge_node_rows(DigestCompare.get(existing, :node_rows) || [], DigestCompare.get(candidate, :node_rows) || [])
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
      node: DigestCompare.get(a, :node) || DigestCompare.get(b, :node),
      relation: DigestCompare.get(a, :relation) || DigestCompare.get(b, :relation),
      depth: DigestCompare.get(a, :depth),
      estimated_rows: max_num(DigestCompare.get(a, :estimated_rows), DigestCompare.get(b, :estimated_rows)),
      actual_rows: max_num(DigestCompare.get(a, :actual_rows), DigestCompare.get(b, :actual_rows)),
      loops: max_num(DigestCompare.get(a, :loops), DigestCompare.get(b, :loops)),
      rows_touched: max_num(DigestCompare.get(a, :rows_touched), DigestCompare.get(b, :rows_touched)),
      estimate_error: max_num(DigestCompare.get(a, :estimate_error), DigestCompare.get(b, :estimate_error))
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

  defp max_cardinality(nil, other), do: other
  defp max_cardinality(other, nil), do: other
  defp max_cardinality(a, b), do: max(a, b)

  defp view_str(nil), do: nil
  defp view_str(view), do: view |> to_string() |> String.replace_prefix("Elixir.", "")
end
