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
    |> fold_dollar_quoted()
    |> fold_escape_strings()
    |> fold_quoted_literals()
    |> fold_numeric_literals()
    |> fold_params()
    |> fold_in_lists()
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

  # $$body$$ / $tag$body$tag$ -> ?   (run first: body is arbitrary, may contain quotes/newlines).
  # The backreference (\1) pairs the open/close tag, so Ecto params ($1, $2) — which have no
  # matching $tag$ close — are left untouched for fold_params/1.
  defp fold_dollar_quoted(sql), do: Regex.replace(~r/\$([a-z0-9_]*)\$.*?\$\1\$/s, sql, "?")

  # E'escape strings' use backslash escaping (e.g. E'O\'Brien') -> ?   (after downcase, E' is e')
  defp fold_escape_strings(sql), do: Regex.replace(~r/\be'(?:[^'\\]|\\.|'')*'/, sql, "?")

  # 'text' and 'escaped '' quotes' -> ?
  # Note: double-quoted "identifiers" are deliberately preserved — they are identifiers, not values.
  defp fold_quoted_literals(sql), do: Regex.replace(~r/'(?:[^']|'')*'/, sql, "?")

  # bare numbers incl. decimals and scientific notation (e.g. LIMIT 50, 1.5e10) -> ?
  # Word boundaries protect digit-bearing identifiers (users_2024, line1, t2).
  defp fold_numeric_literals(sql), do: Regex.replace(~r/\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/, sql, "?")

  # remaining $1, $2 -> $?
  defp fold_params(sql), do: Regex.replace(~r/\$\d+/, sql, "$?")

  # IN ($?, $?, ...) / IN (?, ?) -> IN ($?)   (folds numeric, param, and placeholder lists uniformly)
  defp fold_in_lists(sql), do: Regex.replace(~r/\bin\s*\(\s*(?:\$\?|\?)(?:\s*,\s*(?:\$\?|\?))*\s*\)/, sql, "in ($?)")

  defp collapse_whitespace(sql), do: Regex.replace(~r/\s+/, sql, " ")
end
