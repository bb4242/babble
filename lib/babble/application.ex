defmodule Babble.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {Cluster.Supervisor,
       [Application.get_env(:libcluster, :topologies), [name: Babble.LibClusterSupervisor]]},
      {Babble.Transports.UdpMulticast, []},
      {Babble.Transports.RemotePublisher, []},
      {Babble.TableHeir, []},
      {DynamicSupervisor,
       name: Babble.PubWorkerSupervisor, strategy: :one_for_one, max_restarts: 10, max_seconds: 3},
      {Babble.SubscriptionManager, []},
      {Babble.NodeMonitor, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :rest_for_one, name: Babble.Supervisor]
    res = Supervisor.start_link(children, opts)
    {:ok, _} = Application.ensure_all_started(:libcluster, :permanent)
    res
  end
end
