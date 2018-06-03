defmodule Babble.PubWorker do
  @moduledoc """
  Per-topic worker process responsible for delivering published messages to subscribers
  """
  use GenServer
  use Babble.Constants

  import Babble.Utils

  defmodule State do
    @enforce_keys [:topic]
    defstruct [{:next_pub_times, %{}}, :topic]
  end

  # Client API
  def start_link(topic) do
    GenServer.start_link(__MODULE__, topic, name: worker_name(topic))
  end

  @doc """
  Internal publication API.  Use Babble.publish instead. :)

    iex> Babble.publish("my.topic", key1: :val1, key2: :val2)
    :ok

  """
  def _internal_publish(topic, message, force \\ false) do
    topic = fully_qualified_topic_name(topic)

    pid =
      case Process.whereis(worker_name(topic)) do
        nil ->
          {:ok, new_worker} = start_link(topic)
          new_worker

        existing_worker when is_pid(existing_worker) ->
          existing_worker
      end

    GenServer.cast(pid, {:publish, message, force})
  end

  # Server callbacks
  @impl true
  def init(topic) do
    topic = fully_qualified_topic_name(topic)
    ^topic = :ets.new(topic, [:named_table, :protected, :set])
    {:ok, %State{topic: topic}}
  end

  @impl true
  def handle_cast(
        {:publish, message, force},
        state = %State{topic: topic, next_pub_times: next_pub_times}
      ) do
    # TODO: Insert timestamp into update

    # Insert values into local ETS table
    {msg_kw, msg_map} =
      if is_map(message) do
        {Map.to_list(message), message}
      else
        {message, Enum.into(message, %{})}
      end

    :ets.insert(topic, msg_kw)

    # Publish to all local subscribers
    case Babble.poll(@subscription_topic, [topic]) do
      {:ok, [subs]} ->
        # Get the pid and subscription rate for all subscribers who want delivery
        for {pid, sub} <- subs, sub[:deliver] do
          # TODO: Handle decimated delivery specified by sub[:rate]
          # TODO: include timestamp
          Process.send(pid, {:babble_msg, topic, msg_map}, [])
        end

      {:error, _} ->
        []
    end

    {:noreply, state}
  end

  defp worker_name(topic) do
    String.to_atom(Atom.to_string(__MODULE__) <> "_" <> Atom.to_string(topic))
  end
end
