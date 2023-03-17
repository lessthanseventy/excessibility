defmodule IntegrationTest.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      IntegrationTestWeb.Telemetry,
      # Start the Ecto repository
      IntegrationTest.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: IntegrationTest.PubSub},
      # Start Finch
      {Finch, name: IntegrationTest.Finch},
      # Start the Endpoint (http/https)
      IntegrationTestWeb.Endpoint
      # Start a worker by calling: IntegrationTest.Worker.start_link(arg)
      # {IntegrationTest.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: IntegrationTest.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    IntegrationTestWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
