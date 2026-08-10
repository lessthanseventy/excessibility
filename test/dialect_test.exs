defmodule Excessibility.DialectTest do
  use ExUnit.Case, async: true

  alias Excessibility.Dialect
  alias Excessibility.Dialect.Postgres

  test "resolve/0 defaults to Postgres" do
    assert Dialect.resolve() == Postgres
  end

  test "postgres explain_sql wraps for json plan" do
    assert Postgres.explain_sql("SELECT 1") == "EXPLAIN (FORMAT JSON) SELECT 1"
  end

  test "postgres normalize_extras is a no-op passthrough" do
    assert Postgres.normalize_extras("select 1") == "select 1"
  end
end
