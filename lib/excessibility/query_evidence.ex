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
    |> Enum.group_by(fn {q, _i} -> q.fingerprint end)
    |> Enum.map(fn {fp, pairs} ->
      {first, _} = hd(pairs)

      %{
        fingerprint: fp,
        operation: to_string(first.operation),
        source: to_string(first.source),
        normalized: Map.get(first, :normalized, ""),
        count: length(pairs),
        sequences: Enum.map(pairs, fn {_q, i} -> i end)
      }
    end)
    |> Enum.sort_by(& &1.fingerprint)
  end

  def repeated(queries, opts \\ []) do
    min = Keyword.get(opts, :min_repetitions, @default_min_repetitions)
    total = max(length(queries), 1)

    queries
    |> Enum.filter(&select?/1)
    |> Enum.group_by(& &1.fingerprint)
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
end
