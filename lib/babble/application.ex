defmodule Babble.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      # Starts a worker by calling: Babble.Worker.start_link(arg)
      # {Babble.Worker, arg},
      {Babble.TableHeir, []},
      {DynamicSupervisor, name: Babble.PubWorkerSupervisor, strategy: :one_for_one},
      {Babble.SubscriptionManager, []},
      {Babble.NodeMonitor, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: Babble.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
