defmodule Babble.SubscriptionManager do
  use GenServer
  use Babble.Constants

  defmodule State do
    @doc """
    `monitors` - map(pid() => monitor ref)
    """
    defstruct monitors: %{}
  end

  # Client API
  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  # Server callbacks
  @impl true
  def init(_) do
    Babble.PubWorker._internal_publish(@subscription_topic, %{}, sync: true)
    {:ok, %State{}}
  end

  @impl true
  def handle_call({:subscribe, topic, options}, {pid, _tag}, state = %State{monitors: monitors}) do
    # Ensure we only register subscribers on the local node
    if Node.self() != node(pid) do
      {:reply, {:error, "Cannot register a remote subscriber"}, state}
    else
      existing_subs =
        case Babble.poll(@subscription_topic, [topic]) do
          {:ok, [subs]} -> subs
          {:error, _} -> %{}
        end

      new_subs = Map.put(existing_subs, pid, Enum.into(options, %{}))

      :ok =
        Babble.PubWorker._internal_publish(
          @subscription_topic,
          %{topic => new_subs},
          sync: true,
          remote_publish: :force
        )

      monitor =
        case Map.fetch(monitors, pid) do
          {:ok, m} -> m
          :error -> Process.monitor(pid)
        end

      monitors = Map.put(monitors, pid, monitor)
      {:reply, :ok, %{state | monitors: monitors}}
    end
  end

  def handle_call({:unsubscribe, topic}, {pid, _tag}, state) do
    case Babble.poll(@subscription_topic, [topic]) do
      {:ok, [subs]} ->
        new_subs = Map.drop(subs, [pid])

        # Publish synchronously to guarantee the unsubscribing process will not receive any messages
        # it sends to the topic after the unsubscription call finishes
        :ok =
          Babble.PubWorker._internal_publish(
            @subscription_topic,
            %{topic => new_subs},
            sync: true,
            remote_publish: :force
          )

      _ ->
        :ok
    end

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state = %State{monitors: monitors}) do
    {:ok, all_subs} = Babble.poll(@subscription_topic)

    # Remove pid from all subscriptions
    all_subs = all_subs |> Enum.map(fn {k, v} -> {k, Map.drop(v, [pid])} end) |> Enum.into(%{})

    :ok =
      Babble.PubWorker._internal_publish(
        @subscription_topic,
        all_subs,
        sync: true,
        remote_publish: :force
      )

    # Remove pid from monitors
    monitors = Map.drop(monitors, [pid])

    {:noreply, %{state | monitors: monitors}}
  end
end
