# Configure test endpoint before compiling
Application.put_env(:excessibility, Excessibility.TestEndpoint,
  url: [host: "localhost"],
  secret_key_base: String.duplicate("a", 64),
  pubsub_server: nil,
  http: false,
  server: false
)

# Compile test support files
Code.require_file("test/support/test_endpoint.ex", File.cwd!())
Code.require_file("test/support/scanner_stub.ex", File.cwd!())

# The real-Postgrex privacy regression (#175) needs a live database. When
# DATABASE_URL is set (CI's disposable Postgres, or a local dev DB), start a
# real repo so the `:database`-tagged test runs against genuine adapter
# telemetry. Otherwise exclude that tag so `mix test` stays green with no DB.
database_url = System.get_env("DATABASE_URL")

if database_url do
  Application.put_env(:excessibility, Excessibility.TestRepo,
    url: database_url,
    pool_size: 2
  )

  Code.require_file("test/support/test_repo.ex", File.cwd!())

  case Excessibility.TestRepo.start_link() do
    {:ok, _} -> :ok
    {:error, {:already_started, _}} -> :ok
  end

  ExUnit.start()
else
  ExUnit.start(exclude: [:database])
end

Mox.defmock(Excessibility.LiveViewMock, for: Excessibility.LiveView.Behaviour)
Mox.defmock(Excessibility.BrowserMock, for: Excessibility.BrowserBehaviour)
Mox.defmock(Excessibility.SystemMock, for: Excessibility.SystemBehaviour)
Mox.defmock(Excessibility.ScannerMock, for: Excessibility.ScannerBehaviour)

Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)
Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveViewMock)
Application.put_env(:excessibility, :browser_mod, Excessibility.BrowserMock)
# Reviews scan snapshots through :scanner_mod; default to a no-violation
# stub so unit tests never launch a browser.
Application.put_env(:excessibility, :scanner_mod, Excessibility.ScannerStub)

# Configure test endpoint for HTML attribute extraction tests
Application.put_env(:excessibility, :endpoint, Excessibility.TestEndpoint)

# Start the test endpoint
{:ok, _} = Excessibility.TestEndpoint.start_link()
