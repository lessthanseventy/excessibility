import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Uf5PlT+ra1w6ogZiI0QAyhyPCL/guQHZ6BffPY3AwrYD4SheLtFJ1pggF9/T2iIA",
  server: false

# Excessibility: point it at the app's endpoint for <head> extraction and
# snapshot output. axe/pa11y browser scans are disabled in this harness;
# we're exercising the LiveView rules + behavioral analyzers end to end.
config :excessibility,
  endpoint: DemoWeb.Endpoint,
  excessibility_output_path: "test/excessibility",
  # Enables Ecto query capture: excessibility attaches to [:demo, :repo, :query].
  ecto_repos: [Demo.Repo]

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
