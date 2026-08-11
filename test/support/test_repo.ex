defmodule Excessibility.TestRepo do
  @moduledoc """
  A real Postgrex-backed repo used only by the DB-gated privacy regression
  (`test/telemetry_capture_real_postgres_test.exs`). It exists so a genuine
  Ecto/Postgrex `[:excessibility, :test_repo, :query]` telemetry event — the
  adapter boundary that produces query metadata in production — is exercised,
  rather than a hand-built record. The module is always defined (so references in
  the database test compile cleanly), but it only opens a connection via
  `start_link/0` when `DATABASE_URL` is set; otherwise the `database: true` tag is
  excluded and no connection is attempted.
  """
  use Ecto.Repo, otp_app: :excessibility, adapter: Ecto.Adapters.Postgres
end
