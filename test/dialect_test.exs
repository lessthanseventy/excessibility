defmodule Excessibility.DialectTest do
  use ExUnit.Case, async: true

  alias Excessibility.Dialect

  test "resolve/0 defaults to Postgres" do
    assert Dialect.resolve() == Excessibility.Dialect.Postgres
  end

  test "postgres explain_sql wraps for json plan" do
    assert Excessibility.Dialect.Postgres.explain_sql("SELECT 1") == "EXPLAIN (FORMAT JSON) SELECT 1"
  end

  test "postgres normalize_extras is a no-op passthrough" do
    assert Excessibility.Dialect.Postgres.normalize_extras("select 1") == "select 1"
  end
end
