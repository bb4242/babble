defmodule Babble.SubscriptionManager do
  use GenServer

  defmodule State do
    defstruct monitors: %{}
  end

  @subscription_topic "babble.subscriptions"

  # Client API
  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: __MODULE__)
  end

  # Server callbacks
  @impl true
  def init(_) do
    {:ok, %State{}}
  end

  @impl true
  def handle_call({:subscribe, topic, options}, {pid, _tag}, state = %State{monitors: monitors}) do
    # Ensure we only register subscribers on the local node
    if Node.self() != node(pid) do
      raise ArgumentError, message: "Cannot register a remote subscriber!"
    end

    existing_subs =
      case Babble.poll(@subscription_topic, [topic]) do
        {:ok, [subs]} -> subs
        {:error, _} -> %{}
      end
    new_subs = Map.put(existing_subs, pid, options)
    :ok = Babble.publish(@subscription_topic, [{topic, new_subs}])

    monitor = case Map.fetch(monitors, pid) do
                {:ok, m} -> m
                :error -> Process.monitor(pid)
              end
    monitors = Map.put(monitors, pid, monitor)
    {:reply, :ok, %{state | monitors: monitors}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state = %State{monitors: monitors}) do
    {:ok, all_subs} = Babble.poll(@subscription_topic)

    # Remove pid from all subscriptions
    all_subs = all_subs |> Enum.map(fn {k, v} -> {k, Map.drop(v, [pid])} end) |> Enum.into(%{})
    Babble.publish(@subscription_topic, all_subs)

    # Remove pid from monitors
    monitors = Map.drop(monitors, [pid])

    {:noreply, %{state | monitors: monitors}}
  end

end
