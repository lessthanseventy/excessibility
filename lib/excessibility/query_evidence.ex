defmodule Excessibility.QueryEvidence do
  @moduledoc """
  Fingerprint-based query grouping shared by the `ecto_query_analysis` analyzer
  (which wraps it in severity) and `Excessibility.Digest` (which emits it raw).
  Tolerates string values from reloaded `timeline.json` (issue #151).
  """

  @default_min_repetitions 3

  def shapes(queries) do
    queries
    |> Enum.with_index(1)
    |> Enum.group_by(fn {q, _i} -> fingerprint_of(q) end)
    |> Enum.map(fn {fp, pairs} ->
      {first, _} = hd(pairs)

      maybe_put_plan(
        %{
          fingerprint: fp,
          operation: to_string(first.operation),
          source: to_string(first.source),
          normalized: Map.get(first, :normalized, ""),
          count: length(pairs),
          sequences: Enum.map(pairs, fn {_q, i} -> i end)
        },
        first
      )
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  def repeated(queries, opts \\ []) do
    min = Keyword.get(opts, :min_repetitions, @default_min_repetitions)
    total = max(length(queries), 1)

    queries
    |> Enum.filter(&select?/1)
    |> Enum.group_by(&fingerprint_of/1)
    |> Enum.filter(fn {_fp, group} -> length(group) >= min end)
    |> Enum.map(fn {fp, group} ->
      first = hd(group)

      %{
        fingerprint: fp,
        source: to_string(first.source),
        operation: to_string(first.operation),
        repetitions: length(group),
        share: length(group) / total,
        cardinality: nil,
        severity: :advisory
      }
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  def select?(%{operation: op}), do: to_string(op) == "select"
  def select?(_), do: false

  # Plans are per-fingerprint-stable, so the group's representative plan applies
  # to the whole shape. Only attach `:plan` when the representative actually
  # carries a non-nil plan — the common no-plan case keeps a clean shape with no
  # `:plan` key at all.
  defp maybe_put_plan(shape, representative) do
    case Map.get(representative, :plan) do
      nil -> shape
      plan -> Map.put(shape, :plan, plan)
    end
  end

  # Reloaded pre-feature `timeline.json` records lack a `:fingerprint` key but
  # still carry the raw `:query` (or `:source`), so recompute a stable
  # fingerprint on the fly to keep distinct old queries distinct (issue #154).
  defp fingerprint_of(q) do
    Map.get(q, :fingerprint) ||
      Excessibility.SQLFingerprint.fingerprint(Map.get(q, :query, Map.get(q, :source, "")))
  end
end
