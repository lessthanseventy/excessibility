defmodule TestPass.Repo do
  use Ecto.Repo,
    otp_app: :test_pass,
    adapter: Ecto.Adapters.Postgres
end
