defmodule TestPass.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      TestPassWeb.Telemetry,
      # Start the Ecto repository
      TestPass.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: TestPass.PubSub},
      # Start Finch
      {Finch, name: TestPass.Finch},
      # Start the Endpoint (http/https)
      TestPassWeb.Endpoint
      # Start a worker by calling: TestPass.Worker.start_link(arg)
      # {TestPass.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TestPass.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TestPassWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
