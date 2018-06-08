defmodule Babble.NodeMonitor do
  @moduledoc """
  Publishes topics to nodes immediately upon connection
  """
  use GenServer
  use Babble.Constants

  # Initialization
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ok = :net_kernel.monitor_nodes(true)
    publish_control_topics()
    {:ok, []}
  end

  @impl true
  def handle_info({:nodeup, _node}, state) do
    publish_control_topics()
    {:noreply, state}
  end

  def handle_info({:nodedown, _node}, state) do
    {:noreply, state}
  end

  defp publish_control_topics do
    {:ok, table} = Babble.poll(@subscription_topic)
    # TODO: Only deliver this publication to _node, not everyone
    Babble.PubWorker._internal_publish(@subscription_topic, table, remote_publish: :force)
  end
end
