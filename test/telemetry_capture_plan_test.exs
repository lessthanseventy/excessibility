defmodule Excessibility.TelemetryCapturePlanTest do
  # Not async: mutates the global EXCESSIBILITY_QUERY_PLAN env var. Process-dict
  # state is naturally isolated per-test since ExUnit runs each test in its own
  # process.
  use ExUnit.Case

  alias Excessibility.TelemetryCapture

  @ecto_key :excessibility_ecto_queries
  @in_explain_key :excessibility_in_explain
  @warnings_key :excessibility_plan_warnings

  # A canned Postgres `EXPLAIN (FORMAT JSON)` payload. Postgrex returns a single
  # row / single column whose value is the list-wrapped plan tree.
  defp canned_plan do
    [
      %{
        "Plan" => %{
          "Node Type" => "Index Scan",
          "Relation Name" => "products",
          "Plan Rows" => 1
        }
      }
    ]
  end

  # A stub repo that returns a canned EXPLAIN result and counts its own calls in
  # the (per-test) process dictionary so we can assert whether EXPLAIN ran.
  defmodule StubRepo do
    def query(sql, params), do: query(sql, params, [])

    def query(_sql, _params, _opts) do
      Process.put(:stub_repo_calls, Process.get(:stub_repo_calls, 0) + 1)

      {:ok,
       %{
         rows: [
           [
             [
               %{
                 "Plan" => %{
                   "Node Type" => "Index Scan",
                   "Relation Name" => "products",
                   "Plan Rows" => 1
                 }
               }
             ]
           ]
         ]
       }}
    end
  end

  # A stub repo whose EXPLAIN call itself re-emits the ecto telemetry path once,
  # simulating the EXPLAIN's own `[:ecto, :query]` event. The re-entrancy guard
  # must prevent this nested event from being recorded.
  defmodule ReentrantRepo do
    def query(sql, params), do: query(sql, params, [])

    def query(_sql, _params, _opts) do
      TelemetryCapture.handle_ecto_query(
        [:my_app, :repo, :query],
        %{total_time: System.convert_time_unit(1, :millisecond, :native)},
        %{
          source: "products",
          query: "SELECT * FROM products WHERE id = $1",
          repo: __MODULE__
        },
        nil
      )

      {:ok,
       %{
         rows: [
           [
             [
               %{
                 "Plan" => %{
                   "Node Type" => "Index Scan",
                   "Relation Name" => "products",
                   "Plan Rows" => 1
                 }
               }
             ]
           ]
         ]
       }}
    end
  end

  # A stub repo whose EXPLAIN call raises, to exercise crash isolation.
  defmodule RaisingRepo do
    def query(sql, params), do: query(sql, params, [])
    def query(_sql, _params, _opts), do: raise("boom in EXPLAIN")
  end

  setup do
    Process.delete(@ecto_key)
    Process.delete(@in_explain_key)
    Process.delete(@warnings_key)
    Process.delete(:stub_repo_calls)
    System.delete_env("EXCESSIBILITY_QUERY_PLAN")

    on_exit(fn ->
      System.delete_env("EXCESSIBILITY_QUERY_PLAN")
    end)

    :ok
  end

  defp metadata(query, repo, source) do
    %{
      source: source,
      query: query,
      repo: repo,
      params: [1]
    }
  end

  defp fire(query, repo, source) do
    TelemetryCapture.handle_ecto_query(
      [:my_app, :repo, :query],
      %{total_time: System.convert_time_unit(1, :millisecond, :native)},
      metadata(query, repo, source),
      nil
    )
  end

  test "SELECT gains a value-free plan when EXCESSIBILITY_QUERY_PLAN=explain" do
    System.put_env("EXCESSIBILITY_QUERY_PLAN", "explain")

    fire("SELECT * FROM products WHERE id = $1", StubRepo, "products")

    assert [record] = Process.get(@ecto_key)
    assert record.operation == :select
    assert record.plan.fingerprint =~ ~r/^sha256:[0-9a-f]{16}$/
    assert "Index Scan on products" in record.plan.nodes
    assert record.plan.relations == ["products"]

    # Params are used transiently for EXPLAIN, never stored on the record.
    refute Map.has_key?(record, :params)

    # The re-entrancy flag is cleaned up after a successful EXPLAIN.
    assert Process.get(@in_explain_key) == nil

    # canned_plan/0 is referenced so the shape stays in sync with the stub.
    assert canned_plan() |> hd() |> Map.keys() == ["Plan"]
  end

  test "non-SELECT records without a plan and never runs EXPLAIN" do
    System.put_env("EXCESSIBILITY_QUERY_PLAN", "explain")

    fire("INSERT INTO orders (id) VALUES ($1)", StubRepo, "orders")

    assert [record] = Process.get(@ecto_key)
    assert record.operation == :insert
    assert Map.get(record, :plan) == nil
    assert Process.get(:stub_repo_calls, 0) == 0
  end

  test "plan capture is disabled by default and never runs EXPLAIN" do
    fire("SELECT * FROM products WHERE id = $1", StubRepo, "products")

    assert [record] = Process.get(@ecto_key)
    assert record.operation == :select
    assert Map.get(record, :plan) == nil
    assert Process.get(:stub_repo_calls, 0) == 0
  end

  test "re-entrancy guard prevents EXPLAIN's own telemetry from being recorded" do
    System.put_env("EXCESSIBILITY_QUERY_PLAN", "explain")

    fire("SELECT * FROM products WHERE id = $1", ReentrantRepo, "products")

    records = Process.get(@ecto_key)
    # Only the original query is recorded; the nested EXPLAIN telemetry is dropped.
    assert length(records) == 1
    [record] = records
    assert record.plan.fingerprint =~ ~r/^sha256:[0-9a-f]{16}$/
    assert Process.get(@in_explain_key) == nil
  end

  test "a raising EXPLAIN is crash-isolated: record keeps plan nil and a warning is captured" do
    System.put_env("EXCESSIBILITY_QUERY_PLAN", "explain")

    fire("SELECT * FROM products WHERE id = $1", RaisingRepo, "products")

    assert [record] = Process.get(@ecto_key)
    assert record.operation == :select
    assert Map.get(record, :plan) == nil

    warnings = TelemetryCapture.drain_plan_warnings()
    assert warnings != []
    # Draining clears the warnings.
    assert TelemetryCapture.drain_plan_warnings() == []

    # The guard flag is always cleaned up, even on crash.
    assert Process.get(@in_explain_key) == nil
  end

  test "a nil repo yields plan nil without attempting EXPLAIN" do
    System.put_env("EXCESSIBILITY_QUERY_PLAN", "explain")

    fire("SELECT * FROM products WHERE id = $1", nil, "products")

    assert [record] = Process.get(@ecto_key)
    assert record.operation == :select
    assert Map.get(record, :plan) == nil
  end

  test "ANALYZE downgrade warns once per run, not once per query (#159)" do
    System.put_env("EXCESSIBILITY_QUERY_PLAN", "explain_analyze")
    prev = Application.get_env(:excessibility, :query_plan_allow_analyze)
    Application.put_env(:excessibility, :query_plan_allow_analyze, false)
    # The warn-once flag is global to the run; reset it so the assertion is
    # deterministic regardless of test order.
    TelemetryCapture.reset_analyze_downgrade_warning()

    on_exit(fn ->
      if prev == nil,
        do: Application.delete_env(:excessibility, :query_plan_allow_analyze),
        else: Application.put_env(:excessibility, :query_plan_allow_analyze, prev)

      TelemetryCapture.reset_analyze_downgrade_warning()
    end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        # Three SELECTs across the run — each resolves the plan mode and hits the
        # downgrade path, but the warning must appear exactly once.
        fire("SELECT * FROM products WHERE id = $1", StubRepo, "products")
        fire("SELECT * FROM products WHERE id = $2", StubRepo, "products")
        fire("SELECT * FROM products WHERE id = $3", StubRepo, "products")
      end)

    downgrade_lines =
      log
      |> String.split("\n")
      |> Enum.count(&(&1 =~ "downgrading to EXPLAIN"))

    assert downgrade_lines == 1
  end
end
