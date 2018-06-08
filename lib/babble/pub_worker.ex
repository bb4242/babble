defmodule Babble.PubWorker do
  @moduledoc """
  Per-topic worker process responsible for delivering published messages to subscribers
  """
  use GenServer, restart: :transient
  use Babble.Constants

  import Babble.Utils

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
    - `true` Force publishing, even if no remote subscribers exist
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

    # Publish to all local subscribers
    send_to_local_subscribers(topic, {:babble_msg, topic, msg_map}, pub_time_table)

    # Publish to remote subscribers
    for pub_node <- get_publication_nodes(topic, options) do
      :rpc.cast(pub_node, __MODULE__, :_internal_publish, [
        topic,
        message,
        [remote_publish: false]
      ])
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:nodedown, node}, state = %State{topic: topic = {node, _}, table: table}) do
    send_to_local_subscribers(topic, {:babble_remote_topic_disconnect, topic})
    :ets.delete(table)
    {:stop, :normal, state}
  end

  # Helpers

  defp send_to_local_subscribers({pub_node, short_name}, msg, pub_time_table \\ nil) do
    send_to_local_subscribers(pub_node, short_name, msg, pub_time_table)
    send_to_local_subscribers(:*, short_name, msg, pub_time_table)
  end

  defp send_to_local_subscribers(node, short_name, msg, pub_time_table) do
    now = System.monotonic_time(:milliseconds)

    case Babble.poll(@subscription_topic, [{node, short_name}]) do
      {:ok, [subs]} ->
        # Get the pid and subscription rate for all subscribers who want delivery
        for {pid, sub} <- subs, sub[:deliver] == true do
          # TODO: include timestamp in message
          rate = sub[:rate]

          next_pub_time =
            if is_nil(pub_time_table) do
              now
            else
              case :ets.lookup(pub_time_table, pid) do
                [{^pid, pt}] -> pt
                [] -> now
              end
            end

          cond do
            rate == :on_publish ->
              Process.send(pid, msg, [])

            is_number(rate) and now >= next_pub_time ->
              Process.send(pid, msg, [])
              :ets.insert(pub_time_table, [{pid, now + 1000 / rate}])

            true ->
              nil
          end
        end

      {:error, _} ->
        nil
    end
  end

  defp get_publication_nodes(topic, options) do
    remote_pub = options[:remote_publish]

    cond do
      remote_pub == true ->
        Node.list()

      remote_pub == false ->
        []

      true ->
        Enum.filter(Node.list(), fn node -> is_remote_subscriber?(node, topic) end)
    end
  end

  defp is_remote_subscriber?(sub_node, {pub_node, short_name}) do
    is_remote_subscriber?(sub_node, pub_node, short_name) or
      is_remote_subscriber?(sub_node, :*, short_name)
  end

  defp is_remote_subscriber?(sub_node, pub_node, short_name) do
    with {:ok, [subs]} <- Babble.poll({sub_node, @subscription_topic}, [{pub_node, short_name}]),
         true <- map_size(subs) > 0 do
      true
    else
      _ ->
        false
    end
  end
end
