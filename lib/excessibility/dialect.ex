defmodule Excessibility.Dialect do
  @moduledoc """
  Seam isolating the few genuinely dialect-specific SQL behaviors so a new
  database dialect is a drop-in module + one config line, not a core refactor.
  Only Postgres ships today (the Ecto reference adapter).
  """

  @callback normalize_extras(String.t()) :: String.t()
  @callback explain_sql(String.t()) :: String.t()
  @callback parse_plan(term()) :: map() | nil

  @doc "Resolve the configured dialect module (default Postgres)."
  def resolve, do: :excessibility |> Application.get_env(:sql_dialect, :postgres) |> module_for()

  defp module_for(:postgres), do: Excessibility.Dialect.Postgres
  defp module_for(mod) when is_atom(mod), do: mod
end
