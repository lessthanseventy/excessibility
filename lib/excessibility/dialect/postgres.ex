defmodule Excessibility.Dialect.Postgres do
  @moduledoc "Postgres dialect: JSON EXPLAIN + plan parsing. Generic normalization is shared."
  @behaviour Excessibility.Dialect

  @impl true
  def normalize_extras(sql), do: sql

  @impl true
  def explain_sql(sql), do: "EXPLAIN (FORMAT JSON) " <> sql

  @impl true
  def parse_plan(explain_json), do: Excessibility.QueryPlan.summarize(explain_json)
end
