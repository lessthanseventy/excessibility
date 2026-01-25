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

ExUnit.start()

# Start ChromicPDF if Chrome is available, otherwise skip screenshot tests
case ChromicPDF.start_link(name: ChromicPDF) do
  {:ok, _} ->
    ExUnit.configure(exclude: [])

  {:error, reason} ->
    IO.warn("ChromicPDF failed to start: #{inspect(reason)}. Skipping screenshot tests.")
    ExUnit.configure(exclude: [screenshot: true])
end

Mox.defmock(Excessibility.LiveViewMock, for: Excessibility.LiveView.Behaviour)
Mox.defmock(Excessibility.BrowserMock, for: Excessibility.BrowserBehaviour)
Mox.defmock(Excessibility.SystemMock, for: Excessibility.SystemBehaviour)

Application.put_env(:excessibility, :system_mod, Excessibility.SystemMock)
Application.put_env(:excessibility, :live_view_mod, Excessibility.LiveViewMock)
Application.put_env(:excessibility, :browser_mod, Excessibility.BrowserMock)

# Configure test endpoint for HTML attribute extraction tests
Application.put_env(:excessibility, :endpoint, Excessibility.TestEndpoint)

# Start the test endpoint
{:ok, _} = Excessibility.TestEndpoint.start_link()
