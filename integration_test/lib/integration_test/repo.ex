defmodule IntegrationTest.Repo do
  use Ecto.Repo,
    otp_app: :integration_test,
    adapter: Ecto.Adapters.Postgres
end
