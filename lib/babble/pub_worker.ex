defmodule Babble.PubWorker do
  @moduledoc """
  Per-topic worker process responsible for delivering published messages to subscribers
  """
  use GenServer, restart: :transient
  use Babble.Constants

  import Babble.Utils

  import Babble.Transports.RemotePublisher,
    only: [remote_publish: 7, update_pub_time: 4, update_pub_time: 3]

  defmodule State do
    @moduledoc "State for PubWorker"
    @enforce_keys [:pub_time_table, :topic, :table]
    defstruct [:pub_time_table, :topic, :table]
  end

  # Client API
  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic, name: table_name(topic))
  end

  @doc """
  Internal-only publication API. Use `Babble.publish/2` instead. :)

  ## Valid `options`
  - `:sync :: boolean()` Whether to publish synchronously or not. If `sync` is `true`, the underlying ETS table
     will have been updated, and all subscribers notified, before the function returns
  - `:remote_publish :: true | false | :default` How to decide whether to publish to remote nodes
    - `:force` Force publishing, even if no remote subscribers exist
    - `false` Do not publish, even if remote subscribers exist
    - `:default` Publish according to whether remote subscribers exist
  """
  def _internal_publish(topic, message, options \\ []) do
    pid =
      case Process.whereis(table_name(topic)) do
        nil ->
          {:ok, new_worker} =
            DynamicSupervisor.start_child(Babble.PubWorkerSupervisor, {__MODULE__, topic})

          new_worker

        existing_worker when is_pid(existing_worker) ->
          existing_worker
      end

    fun =
      case options[:sync] do
        true -> &GenServer.call/2
        _ -> &GenServer.cast/2
      end

    fun.(pid, {:publish, message, options})
  end

  # Server callbacks
  @impl true
  def init(topic) do
    # Instantiate the main topic table
    topic = {node, _} = fully_qualified_topic_name(topic)
    table = table_name(topic)
    {:ok, ^table} = Babble.TableHeir.get_table(table)

    # Instantiate the companion publish time table
    pub_time_table_name = String.to_atom("pub_times:" <> Atom.to_string(table))
    pub_time_table = :ets.new(pub_time_table_name, [:named_table, :protected, :set])

    # If this is a remote topic, monitor the remote node so we can
    # delete the table when the node goes down
    if node != Node.self() do
      Node.monitor(node, true)
    end

    {:ok, %State{topic: topic, table: table, pub_time_table: pub_time_table}}
  end

  @impl true
  def handle_call(msg = {:publish, _message, _options}, _, state) do
    {:noreply, new_state} = handle_cast(msg, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(
        {:publish, message, options},
        state = %State{topic: topic, table: table, pub_time_table: pub_time_table}
      ) do
    # TODO: Insert timestamp into update

    # Insert values into local ETS table
    {msg_kw, msg_map} =
      if is_map(message) do
        {Map.to_list(message), message}
      else
        {message, Enum.into(message, %{})}
      end

    :ets.insert(table, msg_kw)

    # Deliver to all subscribers
    deliver(pub_time_table, topic, msg_map, options)

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state = %State{topic: topic = {node, _}, table: table}) do
    for {sub_pid, _} <- get_subscribers(topic), node(sub_pid) == node() do
      send(sub_pid, {:babble_remote_topic_disconnect, topic})
    end

    :ets.delete(table)
    {:stop, :normal, state}
  end

  # Helpers

  # TODO: Monitor all subscriber pids and delete their entries in pub_time_table when they exit

  @doc """
  Return a map of all (local and remote) subscribers to the topic
  """
  @spec get_subscribers({node(), String.t()}) :: %{pid() => %{}}
  def get_subscribers(topic = {_pub_node, short_name}) do
    # Get subscribers across all nodes, including the local one
    # Include the wildcard topic
    for n <- Node.list([:this, :connected]), t <- [topic, {:*, short_name}] do
      case Babble.poll({n, @subscription_topic}, [t]) do
        {:ok, [subs]} -> subs
        _ -> %{}
      end
    end
    |> List.foldl(%{}, &Map.merge/2)
  end

  def deliver(pub_time_table, topic, message, options) do
    subs = get_subscribers(topic)
    now = System.monotonic_time(:milliseconds)

    remote_pub = options[:remote_publish]

    case remote_pub do
      :force ->
        for n <- Node.list() do
          remote_publish(n, topic, message, :tcp, now, pub_time_table, subs)
        end

      _ ->
        deliver(
          pub_time_table,
          now,
          topic,
          message,
          Map.to_list(subs),
          subs,
          remote_pub
        )
    end
  end

  # No more subscribers to process
  def deliver(_pub_time_table, _now, _topic, _message, [], _all_subs, _remote_publish), do: :ok

  # Local subscribers with deliver==true
  def deliver(
        pub_time_table,
        now,
        topic,
        message,
        [{sub_pid, %{deliver: deliver, rate: rate}} | rest],
        all_subs,
        remote_publish
      )
      when node(sub_pid) == node() and deliver == true do
    wrapped_msg = {:babble_msg, topic, message}
    next_pub_time = get_next_pub_time(pub_time_table, now, sub_pid)

    cond do
      rate == :on_publish ->
        send(sub_pid, wrapped_msg)
        update_pub_time(pub_time_table, sub_pid, now)

      is_number(rate) and now >= next_pub_time ->
        send(sub_pid, wrapped_msg)
        update_pub_time(pub_time_table, sub_pid, now, rate)

      true ->
        nil
    end

    deliver(pub_time_table, now, topic, message, rest, all_subs, remote_publish)
  end

  # Remote subscribers
  def deliver(
        pub_time_table,
        now,
        topic,
        message,
        [{sub_pid, %{transport: transport}} | rest],
        all_subs,
        remote_publish
      )
      when node(sub_pid) != node() and remote_publish != false do
    next_pub_time = get_next_pub_time(pub_time_table, now, sub_pid)

    if now >= next_pub_time do
      remote_publish(node(sub_pid), topic, message, transport, now, pub_time_table, all_subs)
    end

    deliver(pub_time_table, now, topic, message, rest, all_subs, remote_publish)
  end

  # Skip local subscribers with deliver==false or remote subscribers when remote_publish==false
  def deliver(
        pub_time_table,
        now,
        topic,
        message,
        [{sub_pid, %{deliver: deliver}} | rest],
        all_subs,
        remote_publish
      )
      when (node(sub_pid) == node() and deliver == false) or
             (node(sub_pid) != node() and remote_publish == false) do
    deliver(pub_time_table, now, topic, message, rest, all_subs, remote_publish)
  end

  # Get the next time to publish the topic for the specified subscriber PID
  def get_next_pub_time(pub_time_table, now, sub_pid) do
    case :ets.lookup(pub_time_table, sub_pid) do
      [{^sub_pid, next_pub_time}] -> next_pub_time
      [] -> now
    end
  end
end
