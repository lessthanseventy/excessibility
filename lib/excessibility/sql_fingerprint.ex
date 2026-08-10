defmodule Excessibility.SQLFingerprint do
  @moduledoc """
  Normalizes SQL into a stable, value-free shape and derives a fingerprint.

  Postgres-oriented (the Ecto reference adapter). Ecto emits parameterized SQL
  (`$1`, `$2` …) with bind values already separated, so normalization only has
  to canonicalize whitespace/case, fold `IN (...)` arity, and scrub the few
  inline literals that appear in fragments. The fingerprint is derived from the
  normalized string, so grouping (N+1, compare) depends on this being correct —
  see the leak-guard tests.
  """

  @doc """
  Normalize SQL to a stable, value-free string. The generic folds here are
  dialect-agnostic; any dialect-specific normalization is applied last via
  `Excessibility.Dialect.normalize_extras/1` (no-op for Postgres today).
  """
  def normalize(sql) when is_binary(sql) do
    sql
    |> String.downcase()
    |> fold_quoted_literals()
    |> fold_param_lists()
    |> fold_params()
    |> fold_numeric_literals()
    |> collapse_whitespace()
    |> String.trim()
    |> Excessibility.Dialect.resolve().normalize_extras()
  end

  def normalize(_), do: ""

  @doc ~S'Fingerprint SQL as `"sha256:<16 hex>"`.'
  def fingerprint(sql) do
    hash =
      sql
      |> normalize()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 16)

    "sha256:" <> hash
  end

  # 'text' and 'escaped '' quotes' -> ?   (do this first, before digit folding)
  defp fold_quoted_literals(sql), do: Regex.replace(~r/'(?:[^']|'')*'/, sql, "?")

  # IN ($1, $2, $3) / IN (?, ?) -> IN ($?)
  defp fold_param_lists(sql), do: Regex.replace(~r/\bin\s*\(\s*(?:\$\d+|\?)(?:\s*,\s*(?:\$\d+|\?))*\s*\)/, sql, "in ($?)")

  # remaining $1, $2 -> $?
  defp fold_params(sql), do: Regex.replace(~r/\$\d+/, sql, "$?")

  # bare numbers (e.g. LIMIT 50) -> ?
  defp fold_numeric_literals(sql), do: Regex.replace(~r/\b\d+\b/, sql, "?")

  defp collapse_whitespace(sql), do: Regex.replace(~r/\s+/, sql, " ")
end
