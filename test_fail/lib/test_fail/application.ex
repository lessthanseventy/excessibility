defmodule TestFail.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      TestFailWeb.Telemetry,
      # Start the Ecto repository
      TestFail.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: TestFail.PubSub},
      # Start Finch
      {Finch, name: TestFail.Finch},
      # Start the Endpoint (http/https)
      TestFailWeb.Endpoint
      # Start a worker by calling: TestFail.Worker.start_link(arg)
      # {TestFail.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TestFail.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TestFailWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
