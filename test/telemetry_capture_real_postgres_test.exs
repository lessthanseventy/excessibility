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
  DB); `test_helper.exs` excludes the `:database` tag otherwise.
  """
  use ExUnit.Case

  alias Excessibility.TelemetryCapture

  @moduletag :database

  @output_path "test/excessibility"
  @digest_path "test/excessibility/digest.json"

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

    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: 50},
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
end
