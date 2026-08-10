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
    |> strip_comments()
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

  # Remove SQL line (`-- …`) and block (`/* … */`) comments *before* any value
  # folding, so comment contents (tracing annotations, tenant tags, etc.) never
  # reach the digest. A single left-to-right scanner tracks literal/identifier
  # context so a comment marker *inside* a string, dollar-quoted body, or quoted
  # identifier is copied verbatim rather than mistaken for a comment start.
  # Comments are replaced with a space to preserve token separation; the later
  # whitespace collapse tidies up. Comment-free SQL is returned unchanged, so
  # fingerprints stay stable and comments never affect grouping.
  defp strip_comments(sql), do: scan(sql, :normal, "")

  # End of input in any state.
  defp scan(<<>>, _state, acc), do: acc

  # --- line comment: drop everything up to (and re-emit) the newline ---
  defp scan(<<"\n", rest::binary>>, :line, acc), do: scan(rest, :normal, <<acc::binary, "\n">>)
  defp scan(<<_c, rest::binary>>, :line, acc), do: scan(rest, :line, acc)

  # --- block comment: Postgres allows nesting, so track depth ---
  defp scan(<<"/*", rest::binary>>, {:block, depth}, acc), do: scan(rest, {:block, depth + 1}, acc)
  defp scan(<<"*/", rest::binary>>, {:block, 1}, acc), do: scan(rest, :normal, <<acc::binary, " ">>)
  defp scan(<<"*/", rest::binary>>, {:block, depth}, acc), do: scan(rest, {:block, depth - 1}, acc)
  defp scan(<<_c, rest::binary>>, {:block, _} = state, acc), do: scan(rest, state, acc)

  # --- single-quoted string literal: copy verbatim, honour '' escape ---
  defp scan(<<"''", rest::binary>>, :squote, acc), do: scan(rest, :squote, <<acc::binary, "''">>)
  defp scan(<<"'", rest::binary>>, :squote, acc), do: scan(rest, :normal, <<acc::binary, "'">>)
  defp scan(<<c, rest::binary>>, :squote, acc), do: scan(rest, :squote, <<acc::binary, c>>)

  # --- double-quoted identifier: copy verbatim, honour "" escape ---
  defp scan(<<"\"\"", rest::binary>>, :dquote, acc), do: scan(rest, :dquote, <<acc::binary, "\"\"">>)
  defp scan(<<"\"", rest::binary>>, :dquote, acc), do: scan(rest, :normal, <<acc::binary, "\"">>)
  defp scan(<<c, rest::binary>>, :dquote, acc), do: scan(rest, :dquote, <<acc::binary, c>>)

  # --- normal SQL: recognise comment/literal/identifier starts ---
  defp scan(<<"--", rest::binary>>, :normal, acc), do: scan(rest, :line, <<acc::binary, " ">>)
  defp scan(<<"/*", rest::binary>>, :normal, acc), do: scan(rest, {:block, 1}, <<acc::binary, " ">>)
  defp scan(<<"'", rest::binary>>, :normal, acc), do: scan(rest, :squote, <<acc::binary, "'">>)
  defp scan(<<"\"", rest::binary>>, :normal, acc), do: scan(rest, :dquote, <<acc::binary, "\"">>)

  defp scan(<<"$", rest::binary>> = bin, :normal, acc) do
    # Copy a dollar-quoted body verbatim so `--`/`/*` inside it are not stripped.
    # Ecto params ($1, $2 …) have no matching close tag, so take_dollar_quoted/1
    # returns :error and the lone `$` is copied like any other byte.
    case take_dollar_quoted(bin) do
      {:ok, quoted, tail} -> scan(tail, :normal, <<acc::binary, quoted::binary>>)
      :error -> scan(rest, :normal, <<acc::binary, "$">>)
    end
  end

  defp scan(<<c, rest::binary>>, :normal, acc), do: scan(rest, :normal, <<acc::binary, c>>)

  # Match a full `$tag$ … $tag$` span at the head of `bin` and return it verbatim
  # with the remainder. Tag is `[a-z0-9_]*` (already downcased). Returns :error
  # when the head is not a complete dollar-quoted literal (e.g. a `$1` param or an
  # unterminated body).
  defp take_dollar_quoted(bin) do
    case Regex.run(~r/^\$[a-z0-9_]*\$/, bin) do
      [open] ->
        open_len = byte_size(open)
        after_open = binary_part(bin, open_len, byte_size(bin) - open_len)

        case :binary.match(after_open, open) do
          {pos, _len} ->
            span_len = open_len + pos + byte_size(open)
            quoted = binary_part(bin, 0, span_len)
            rest = binary_part(bin, span_len, byte_size(bin) - span_len)
            {:ok, quoted, rest}

          :nomatch ->
            :error
        end

      nil ->
        :error
    end
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
