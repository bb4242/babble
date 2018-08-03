defmodule Babble.NodeMonitor do
  @moduledoc """
  Publishes topics to nodes immediately upon connection
  """
  use GenServer
  use Babble.Constants

  require Logger

  # Initialization
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_) do
    :ok = :net_kernel.monitor_nodes(true)
    publish_control_topics(node())
    {:ok, []}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    {:ok, _task_pid} = Task.start_link(fn -> publish_control_topics(node) end)
    {:noreply, state}
  end

  def handle_info({:nodedown, _node}, state) do
    {:noreply, state}
  end

  defp publish_control_topics(node) do
    # Wait for a Babble.Transports.RemotePublisher process to register itself
    # on the remote node before publishing, since we might get a nodeup message
    # while the Babble application is still starting up on the remote node
    wait_for_remote_publisher(node, 20)

    {:ok, table} = Babble.poll(@subscription_topic)
    # TODO: Only deliver this publication to _node, not everyone
    Babble.PubWorker._internal_publish(@subscription_topic, table, remote_publish: :force)
  end

  defp wait_for_remote_publisher(node, 0) do
    Logger.error(
      "Could not contact Babble.Transports.RemotePublisher process on #{node}! Subscriptions for topics from that node may not be delivered correctly"
    )
  end

  defp wait_for_remote_publisher(node, remaining_attempts) do
    case :rpc.call(node, Process, :whereis, [Babble.Transports.RemotePublisher]) do
      pid when is_pid(pid) ->
        Logger.info("Remote publisher is up on #{node}")
        :ok

      _ ->
        Logger.warn("Remote publisher not up yet on #{node}. Trying again")
        Process.sleep(1000)
        wait_for_remote_publisher(node, remaining_attempts - 1)
    end
  end
end
