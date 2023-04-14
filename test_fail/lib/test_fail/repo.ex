defmodule TestFail.Repo do
  use Ecto.Repo,
    otp_app: :test_fail,
    adapter: Ecto.Adapters.Postgres
end
