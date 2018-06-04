defmodule Babble.PubWorker do
  @moduledoc """
  Per-topic worker process responsible for delivering published messages to subscribers
  """
  use GenServer
  use Babble.Constants

  import Babble.Utils

  defmodule State do
    @moduledoc "State for PubWorker"
    @enforce_keys [:topic, :table]
    defstruct [{:next_pub_times, %{}}, :topic, :table]
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
          {:ok, new_worker} = start_link(topic)
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
    topic = {node, _} = fully_qualified_topic_name(topic)
    table = table_name(topic)
    # TODO: Set heir on table, and re-acquire if it already exists
    ^table = :ets.new(table, [:named_table, :protected, :set])

    # If this is a remote topic, monitor the remote node so we can
    # delete the table when the node goes down
    if node != Node.self() do
      Node.monitor(node, true)
    end

    {:ok, %State{topic: topic, table: table}}
  end

  @impl true
  def handle_call(msg = {:publish, _message, _options}, _, state) do
    {:noreply, new_state} = handle_cast(msg, state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(
        {:publish, message, options},
        state = %State{topic: topic, table: table, next_pub_times: _next_pub_times}
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
    send_to_local_subscribers(topic, {:babble_msg, topic, msg_map})

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
  def handle_info({:nodedown, node}, state = %State{topic: topic = {node, _}}) do
    send_to_local_subscribers(topic, {:babble_remote_topic_disconnect, topic})
    {:stop, :normal, state}
  end

  # Helpers

  defp send_to_local_subscribers(topic, msg) do
    case Babble.poll(@subscription_topic, [topic]) do
      {:ok, [subs]} ->
        # Get the pid and subscription rate for all subscribers who want delivery
        for {pid, sub} <- subs, sub[:deliver] do
          # TODO: Handle decimated delivery specified by sub[:rate]
          # TODO: include timestamp
          Process.send(pid, msg, [])
        end

      {:error, _} ->
        []
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

  defp is_remote_subscriber?(node, topic) do
    with {:ok, [subs]} <-
           Babble.poll({node, @subscription_topic}, [fully_qualified_topic_name(topic)]),
         true <- map_size(subs) > 0 do
      true
    else
      _ ->
        false
    end
  end
end
