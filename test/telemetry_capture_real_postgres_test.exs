defmodule Excessibility.TelemetryCaptureRealPostgresTest do
  @moduledoc """
  Issue #175: the committed #166 privacy regression builds the query metadata by
  hand (`EctoQueries.build_query_record/2`), so it never crosses the real
  Ecto/Postgrex adapter boundary that produces that metadata in production — the
  suite could stay green while that boundary regressed.

  This test executes the reported SQL shapes through a **real repo** against a
  disposable PostgreSQL database, captures the genuine
  `[:excessibility, :test_repo, :query]` telemetry event, builds the digest, and
  scans the complete emitted artifact for leaks.

  Runs only when `DATABASE_URL` is set (CI's Postgres service, or a local dev
  DB); `test_helper.exs` excludes the `database: true` tag otherwise.

  Issue #185 additionally guards the *timing* privacy criterion from #175: the
  captured event carries a native `duration` measurement, and neither it nor any
  derived millisecond value may reach the value-free digest. A distinctive
  duration canary plus a recursive scan that rejects numeric values under
  timing-shaped keys makes a future timing leak fail loudly, while the intended
  `capture.timing: "non_comparable"` string sentinel stays allowed and asserted.
  """
  use ExUnit.Case

  alias Excessibility.TelemetryCapture

  @moduletag :database

  @output_path "test/excessibility"
  @digest_path "test/excessibility/digest.json"

  # A distinctive, generic native-time duration canary (issue #185). Large and
  # unmistakable so both it and its derived-millisecond value are trivially
  # detectable in the raw digest; nothing like the previous ambiguous `50`.
  @duration_canary 424_242_424_000_000

  # Timing-shaped key matcher for the recursive digest scan: exact timing words,
  # or the common numeric-timing suffixes. `capture.timing` matches too but only
  # ever holds the allowed *string* sentinel, so the scan rejects numbers only.
  @timing_key_regex ~r/^(duration|timing|elapsed|latency)$|_(ms|us|ns|time|duration|latency|elapsed|seconds)$/

  # A valid Postgres dollar-quoted literal whose outer tag is uppercase and whose
  # body contains a lowercase look-alike tag plus a secret email — the #166 case,
  # now produced by the adapter rather than hand-built.
  @dollar_sql "SELECT $TAG$prefix $tag$ request_email=canary_175@example.com $TAG$ AS dollar_note"

  # A valid escaped E-string: `\\'` is an escaped quote (so the string does not
  # close early) and the `--` inside it must NOT start a comment that truncates
  # the trailing shape. Carries a second secret email.
  @estring_sql "SELECT E'a\\'b -- not a comment canary_175_estr@example.com' AS estr_note, 90909090 AS num"

  setup do
    :ets.whereis(:excessibility_snapshots) != :undefined &&
      :ets.delete_all_objects(:excessibility_snapshots)

    File.rm_rf!(@output_path)
    Application.put_env(:excessibility, :ecto_repos, [Excessibility.TestRepo])
    # A legitimate numeric fixture cardinality: it must survive into the digest,
    # proving literal scrubbing is scoped to SQL and does not strip real metadata.
    System.put_env("EXCESSIBILITY_FIXTURES", ~s({"accounts": 4242}))

    on_exit(fn ->
      TelemetryCapture.detach()
      TelemetryCapture.flush_ecto_queries()
      Application.delete_env(:excessibility, :ecto_repos)
      System.delete_env("EXCESSIBILITY_FIXTURES")

      :ets.whereis(:excessibility_snapshots) != :undefined &&
        :ets.delete_all_objects(:excessibility_snapshots)

      File.rm_rf!(@output_path)
    end)

    :ok
  end

  test "real Ecto/Postgrex telemetry for mixed-case dollar and E-string SQL leaks nothing into the digest" do
    TelemetryCapture.attach()

    # Execute BOTH shapes through the real adapter. Each fires a genuine query
    # telemetry event that our handler records onto this process's dict, exactly
    # as live capture attributes queries fired during an event.
    Excessibility.TestRepo.query!(@dollar_sql)
    Excessibility.TestRepo.query!(@estring_sql)

    # Inject a native duration measurement, exactly as LiveView telemetry does.
    # Neither this value nor its derived millisecond form may reach the digest.
    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: @duration_canary},
      %{socket: %{assigns: %{user_id: 123}, view: MyApp.Live}, params: %{"event" => "save"}},
      nil
    )

    TelemetryCapture.write_snapshots("real_pg_leak_test")

    assert File.exists?(@digest_path)
    raw = File.read!(@digest_path)
    digest = Jason.decode!(raw)

    # Both real queries were captured.
    save_event = Enum.find(digest["events"], &(&1["callback"] == "handle_event:save"))
    assert save_event["queries"]["count"] == 2

    # No secret literal, comment body, or bare numeric literal survives.
    refute raw =~ "canary_175@example.com"
    refute raw =~ "canary_175_estr@example.com"
    refute raw =~ "request_email"
    refute raw =~ "not a comment"
    refute raw =~ "90909090"

    # No timing value survives (issue #185): neither the injected native
    # measurement nor its derived millisecond value appears in the raw artifact,
    # and no numeric value sits under any timing-shaped key anywhere in the tree.
    derived_ms = System.convert_time_unit(@duration_canary, :native, :millisecond)
    refute raw =~ Integer.to_string(@duration_canary)
    refute raw =~ Integer.to_string(derived_ms)
    assert timing_number_violations(digest) == []

    # The intended string sentinel is allowed and present — "not measured for
    # comparison", never a numeric duration.
    assert digest["capture"]["timing"] == "non_comparable"

    # Trailing SQL shape is preserved past both folded literals — the column
    # aliases that FOLLOW the dollar/E-string literals must still be present,
    # proving the fold stopped at the literal boundary rather than swallowing
    # the rest of the statement.
    normalized = Enum.map_join(save_event["queries"]["shapes"], " ", & &1["normalized"])
    assert normalized =~ "dollar_note"
    assert normalized =~ "estr_note"

    # The legitimate numeric fixture cardinality is untouched.
    assert digest["coverage"]["fixtures"]["accounts"] == 4242
  end

  # A DB-free companion (issue #186 lets `@tag database: false` opt back in even
  # with no `DATABASE_URL`, so this runs in the ordinary suite). It proves the
  # timing-canary guard actually bites: a clean digest yields no violation, but a
  # representative numeric timing value copied into an event or query block is
  # caught — so the guard cannot silently pass if timing ever leaks.
  @tag database: false
  test "timing-canary scan rejects a numeric value under a timing-shaped key (#185/#186)" do
    clean = %{
      "capture" => %{"timing" => "non_comparable", "capture_version" => "0.19.0"},
      "coverage" => %{"fixtures" => %{"accounts" => 4242}},
      "events" => [
        %{
          "callback" => "handle_event:save",
          "queries" => %{"count" => 2, "shapes" => [%{"fingerprint" => "sha256:aaa", "count" => 1}]},
          "assigns" => %{
            "total_term_bytes" => 100,
            "shapes" => [%{"name" => "x", "term_bytes" => 50, "delta_bytes" => 0}]
          }
        }
      ]
    }

    # The allowed string sentinel is not a violation; a clean digest is silent.
    assert timing_number_violations(clean) == []

    # A duration copied into the event block is caught...
    poisoned_event = put_in(clean, ["events", Access.at(0), "duration_ms"], 987)
    assert [{path, 987}] = timing_number_violations(poisoned_event)
    assert path =~ "duration_ms"

    # ...and one copied into a query shape is caught too.
    poisoned_query =
      put_in(clean, ["events", Access.at(0), "queries", "shapes", Access.at(0), "elapsed"], @duration_canary)

    assert [{_, @duration_canary}] = timing_number_violations(poisoned_query)
  end

  # Recursively collect `{path, value}` for every *numeric* value sitting under a
  # timing-shaped key. String values (the `capture.timing` sentinel) are allowed.
  defp timing_number_violations(term), do: term |> timing_number_violations("root", []) |> Enum.reverse()

  defp timing_number_violations(map, path, acc) when is_map(map) do
    Enum.reduce(map, acc, fn {key, value}, inner ->
      key = to_string(key)
      child = "#{path}.#{key}"
      inner = if timing_key?(key) and is_number(value), do: [{child, value} | inner], else: inner
      timing_number_violations(value, child, inner)
    end)
  end

  defp timing_number_violations(list, path, acc) when is_list(list) do
    list
    |> Enum.with_index()
    |> Enum.reduce(acc, fn {value, index}, inner ->
      timing_number_violations(value, "#{path}[#{index}]", inner)
    end)
  end

  defp timing_number_violations(_scalar, _path, acc), do: acc

  defp timing_key?(key), do: Regex.match?(@timing_key_regex, key)
end
