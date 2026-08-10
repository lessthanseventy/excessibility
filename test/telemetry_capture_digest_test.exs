defmodule Excessibility.TelemetryCaptureDigestTest do
  use ExUnit.Case

  alias Excessibility.TelemetryCapture
  alias Excessibility.TelemetryCapture.Enrichers.EctoQueries

  @output_path "test/excessibility"
  @digest_path "test/excessibility/digest.json"

  # A raw query carrying secret literal *values* that must never survive into the
  # value-free digest. Normalization scrubs quoted literals to `?`, so these
  # canaries appear only in the raw `query` field the digest deliberately drops.
  @secret_sql "SELECT id FROM accounts WHERE api_token = 'LEAK_CANARY_9f3b2c' AND ssn = '078-05-1120' AND id = 424242"

  setup do
    :ets.whereis(:excessibility_snapshots) != :undefined &&
      :ets.delete_all_objects(:excessibility_snapshots)

    File.rm_rf!(@output_path)

    on_exit(fn ->
      TelemetryCapture.detach()

      :ets.whereis(:excessibility_snapshots) != :undefined &&
        :ets.delete_all_objects(:excessibility_snapshots)

      File.rm_rf!(@output_path)
    end)

    :ok
  end

  test "write_snapshots emits a value-free digest.json alongside timeline.json" do
    TelemetryCapture.attach()

    # Seed a captured Ecto query (with secret literal values) onto the process
    # dict so it flushes onto the handle_event snapshot, exactly as live capture
    # would attribute it.
    record =
      EctoQueries.build_query_record(
        %{total_time: System.convert_time_unit(2, :millisecond, :native)},
        %{source: "accounts", query: @secret_sql, repo: nil}
      )

    Process.put(:excessibility_ecto_queries, [record])

    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: 50},
      %{
        socket: %{assigns: %{user_id: 123, products: [%{id: 1}]}, view: MyApp.Live},
        params: %{"event" => "save"}
      },
      nil
    )

    TelemetryCapture.write_snapshots("digest_write_test")

    assert File.exists?(@digest_path)

    digest = @digest_path |> File.read!() |> Jason.decode!()
    assert digest["schema"] == "excessibility.digest/v1"

    # The query WAS captured (count reflects it) but no raw values leak.
    save_event = Enum.find(digest["events"], &(&1["callback"] == "handle_event:save"))
    assert save_event["queries"]["count"] == 1

    raw = File.read!(@digest_path)
    refute raw =~ "LEAK_CANARY_9f3b2c"
    refute raw =~ "078-05-1120"
    refute raw =~ "api_token = '"
    # Bare (unquoted) numeric literals are scrubbed too, not just quoted values.
    refute raw =~ "424242"
  end

  test "non-object EXCESSIBILITY_FIXTURES JSON is rejected in favor of the object fallback" do
    System.put_env("EXCESSIBILITY_FIXTURES", "[1, 2, 3]")

    on_exit(fn -> System.delete_env("EXCESSIBILITY_FIXTURES") end)

    TelemetryCapture.attach()

    TelemetryCapture.handle_event(
      [:phoenix, :live_view, :handle_event, :stop],
      %{duration: 50},
      %{socket: %{assigns: %{user_id: 123}, view: MyApp.Live}, params: %{"event" => "save"}},
      nil
    )

    TelemetryCapture.write_snapshots("fixtures_guard_test")

    digest = @digest_path |> File.read!() |> Jason.decode!()
    # The list must not flow into coverage.fixtures; it stays an object.
    assert digest["coverage"]["fixtures"] == %{}
  end
end
