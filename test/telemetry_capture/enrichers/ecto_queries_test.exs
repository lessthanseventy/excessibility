defmodule Excessibility.TelemetryCapture.Enrichers.EctoQueriesTest do
  use ExUnit.Case, async: true

  alias Excessibility.TelemetryCapture.Enrichers.EctoQueries

  describe "name/0" do
    test "returns :ecto_queries" do
      assert EctoQueries.name() == :ecto_queries
    end
  end

  describe "cost/0" do
    test "returns :moderate" do
      assert EctoQueries.cost() == :moderate
    end
  end

  describe "enrich/2" do
    test "returns empty queries when no query store in opts" do
      result = EctoQueries.enrich(%{}, [])

      assert result.ecto_queries == []
      assert result.ecto_query_count == 0
      assert result.ecto_total_query_ms == 0
    end

    test "returns queries from store when provided" do
      queries = [
        %{source: "products", operation: :select, duration_ms: 1.2, query: "SELECT * FROM products"},
        %{source: "products", operation: :select, duration_ms: 0.8, query: "SELECT * FROM products"}
      ]

      result = EctoQueries.enrich(%{}, ecto_queries: queries)

      assert length(result.ecto_queries) == 2
      assert result.ecto_query_count == 2
      assert_in_delta result.ecto_total_query_ms, 2.0, 0.01
    end
  end

  describe "attach/0 and detach/0" do
    test "attaches and detaches telemetry handler" do
      assert :ok = EctoQueries.attach()
      assert :ok = EctoQueries.detach()
    end
  end

  describe "get_queries/0 and clear/0" do
    setup do
      EctoQueries.start_store()
      on_exit(fn -> EctoQueries.stop_store() end)
    end

    test "stores and retrieves queries" do
      EctoQueries.record_query(%{
        source: "users",
        operation: :select,
        duration_ms: 1.5,
        query: "SELECT * FROM users",
        repo: Ecto.Repo
      })

      queries = EctoQueries.get_queries()
      assert length(queries) == 1
      assert List.first(queries).source == "users"
    end

    test "clear removes all queries" do
      EctoQueries.record_query(%{source: "users", operation: :select, duration_ms: 1.0, query: "SELECT", repo: nil})
      EctoQueries.clear()

      assert EctoQueries.get_queries() == []
    end
  end
end
