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
  `c:Excessibility.Dialect.normalize_extras/1` (no-op for Postgres today).

  The literal-aware `scan/3` runs first, on the **original-case** SQL: Postgres
  dollar-quote tags (`$TAG$`) and E-string escapes are case-sensitive, so
  lowercasing before scanning could turn look-alike text inside a literal into a
  false closing delimiter and leak literal contents (see #166). The scan folds
  every string / dollar-quoted / E-string literal to `?` and strips comments, so
  only value-free tokens remain; downcasing the scanned result is then safe.
  """
  def normalize(sql) when is_binary(sql) do
    sql
    |> scan(:normal, "")
    |> String.downcase()
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

  # Literal-aware, case-sensitive scan run *before* any downcasing. It strips SQL
  # comments and folds every string / dollar-quoted / E-string literal to `?`, so
  # comment contents (tracing annotations, tenant tags) and literal values never
  # reach the digest. A single left-to-right scanner tracks literal/identifier
  # context so a comment or delimiter marker *inside* a literal is not mistaken
  # for a real one. Postgres dollar tags and E-string escapes are case-sensitive,
  # so this MUST see the original case (#166): a lowercase `$tag$` inside an
  # uppercase-tagged `$TAG$…$TAG$` literal is body content, not a close.
  #
  # Comments and folded literals become `?`/space; the remaining value-free
  # tokens (keywords, identifiers, numbers, params) are downcased by the caller.
  # Double-quoted identifiers are preserved verbatim (they are identifiers, not
  # values) and downcased later like any other identifier.

  # End of input in any state (unterminated literals/comments simply end).
  defp scan(<<>>, _state, acc), do: acc

  # --- line comment: drop everything up to (and re-emit) the newline ---
  defp scan(<<"\n", rest::binary>>, :line, acc), do: scan(rest, :normal, <<acc::binary, "\n">>)
  defp scan(<<_c, rest::binary>>, :line, acc), do: scan(rest, :line, acc)

  # --- block comment: Postgres allows nesting, so track depth ---
  defp scan(<<"/*", rest::binary>>, {:block, depth}, acc), do: scan(rest, {:block, depth + 1}, acc)
  defp scan(<<"*/", rest::binary>>, {:block, 1}, acc), do: scan(rest, :normal, <<acc::binary, " ">>)
  defp scan(<<"*/", rest::binary>>, {:block, depth}, acc), do: scan(rest, {:block, depth - 1}, acc)
  defp scan(<<_c, rest::binary>>, {:block, _} = state, acc), do: scan(rest, state, acc)

  # --- single-quoted string literal: skip body (already folded to `?` on open),
  #     honour the '' escape so a doubled quote does not close the literal ---
  defp scan(<<"''", rest::binary>>, :squote, acc), do: scan(rest, :squote, acc)
  defp scan(<<"'", rest::binary>>, :squote, acc), do: scan(rest, :normal, acc)
  defp scan(<<_c, rest::binary>>, :squote, acc), do: scan(rest, :squote, acc)

  # --- E'…' escape string: skip body, honour both the \\<char> backslash escape
  #     and the '' escape so neither closes the literal early (#166) ---
  defp scan(<<"\\", _c, rest::binary>>, :estring, acc), do: scan(rest, :estring, acc)
  defp scan(<<"''", rest::binary>>, :estring, acc), do: scan(rest, :estring, acc)
  defp scan(<<"'", rest::binary>>, :estring, acc), do: scan(rest, :normal, acc)
  defp scan(<<_c, rest::binary>>, :estring, acc), do: scan(rest, :estring, acc)

  # --- double-quoted identifier: copy verbatim, honour "" escape ---
  defp scan(<<"\"\"", rest::binary>>, :dquote, acc), do: scan(rest, :dquote, <<acc::binary, "\"\"">>)
  defp scan(<<"\"", rest::binary>>, :dquote, acc), do: scan(rest, :normal, <<acc::binary, "\"">>)
  defp scan(<<c, rest::binary>>, :dquote, acc), do: scan(rest, :dquote, <<acc::binary, c>>)

  # --- normal SQL: recognise comment/literal/identifier starts ---
  defp scan(<<"--", rest::binary>>, :normal, acc), do: scan(rest, :line, <<acc::binary, " ">>)
  defp scan(<<"/*", rest::binary>>, :normal, acc), do: scan(rest, {:block, 1}, <<acc::binary, " ">>)

  # E-string: `E'` / `e'` only when the E starts a token (word boundary), so an
  # identifier ending in e (e.g. `date'…'`) is not misread as an E-string.
  defp scan(<<c, "'", rest::binary>>, :normal, acc) when c in [?e, ?E] do
    if word_boundary?(acc),
      do: scan(rest, :estring, <<acc::binary, "?">>),
      else: scan(<<"'", rest::binary>>, :normal, <<acc::binary, c>>)
  end

  defp scan(<<"'", rest::binary>>, :normal, acc), do: scan(rest, :squote, <<acc::binary, "?">>)
  defp scan(<<"\"", rest::binary>>, :normal, acc), do: scan(rest, :dquote, <<acc::binary, "\"">>)

  defp scan(<<"$", rest::binary>> = bin, :normal, acc) do
    # Fold a complete dollar-quoted literal to `?`. An open `$tag$` with no
    # matching close is an unterminated literal (invalid SQL, so Ecto never emits
    # it) — fold the remainder to `?` too, mirroring the squote/estring EOF paths
    # so the value-free invariant holds for every literal kind. A lone `$` with no
    # `$tag$`-shaped open (Ecto params $1, $2 …) is copied like any other byte and
    # fold_params/1 rewrites it to `$?` later.
    case take_dollar_quoted(bin) do
      {:ok, tail} -> scan(tail, :normal, <<acc::binary, "?">>)
      :unterminated -> <<acc::binary, "?">>
      :no_tag -> scan(rest, :normal, <<acc::binary, "$">>)
    end
  end

  defp scan(<<c, rest::binary>>, :normal, acc), do: scan(rest, :normal, <<acc::binary, c>>)

  # True when acc does not end in an identifier character, i.e. the next byte
  # would start a fresh token. Empty acc counts as a boundary.
  defp word_boundary?(<<>>), do: true

  defp word_boundary?(acc) do
    <<_::binary-size(byte_size(acc) - 1), last>> = acc
    last not in ?a..?z and last not in ?A..?Z and last not in ?0..?9 and last != ?_
  end

  # Classify the head of `bin`. Tags are matched **case-sensitively**
  # (`[A-Za-z0-9_]*`), so `$TAG$` only closes on another `$TAG$`. Returns:
  #   {:ok, tail}    — a complete `$tag$ … $tag$` span; `tail` is what follows it
  #   :unterminated  — a `$tag$`-shaped open with no matching close (invalid SQL)
  #   :no_tag        — no `$tag$`-shaped open at all (e.g. a `$1` param)
  defp take_dollar_quoted(bin) do
    case Regex.run(~r/^\$[A-Za-z0-9_]*\$/, bin) do
      [open] ->
        open_len = byte_size(open)
        after_open = binary_part(bin, open_len, byte_size(bin) - open_len)

        case :binary.match(after_open, open) do
          {pos, _len} ->
            span_len = open_len + pos + byte_size(open)
            rest = binary_part(bin, span_len, byte_size(bin) - span_len)
            {:ok, rest}

          :nomatch ->
            :unterminated
        end

      nil ->
        :no_tag
    end
  end

  # bare numbers incl. decimals and scientific notation (e.g. LIMIT 50, 1.5e10) -> ?
  # Word boundaries protect digit-bearing identifiers (users_2024, line1, t2).
  defp fold_numeric_literals(sql), do: Regex.replace(~r/\b\d+(?:\.\d+)?(?:e[+-]?\d+)?\b/, sql, "?")

  # remaining $1, $2 -> $?
  defp fold_params(sql), do: Regex.replace(~r/\$\d+/, sql, "$?")

  # IN ($?, $?, ...) / IN (?, ?) -> IN ($?)   (folds numeric, param, and placeholder lists uniformly)
  defp fold_in_lists(sql), do: Regex.replace(~r/\bin\s*\(\s*(?:\$\?|\?)(?:\s*,\s*(?:\$\?|\?))*\s*\)/, sql, "in ($?)")

  defp collapse_whitespace(sql), do: Regex.replace(~r/\s+/, sql, " ")
end
