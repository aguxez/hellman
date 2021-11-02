defmodule Hellman.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      HellmanWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Hellman.PubSub},
      HellmanWeb.Presence,
      Hellman.PageBrain,
      # Start the Endpoint (http/https)
      HellmanWeb.Endpoint
      # Start a worker by calling: Hellman.Worker.start_link(arg)
      # {Hellman.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Hellman.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HellmanWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
