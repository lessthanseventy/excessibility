defmodule Excessibility.TestRepo do
  @moduledoc """
  A real Postgrex-backed repo used only by the DB-gated privacy regression
  (`test/telemetry_capture_real_postgres_test.exs`). It exists so a genuine
  Ecto/Postgrex `[:excessibility, :test_repo, :query]` telemetry event — the
  adapter boundary that produces query metadata in production — is exercised,
  rather than a hand-built record. Started only when `DATABASE_URL` is set;
  otherwise the tag `:database` is excluded and this module is never loaded.
  """
  use Ecto.Repo, otp_app: :excessibility, adapter: Ecto.Adapters.Postgres
end
