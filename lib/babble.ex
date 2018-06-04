defmodule Babble do
  @moduledoc """
  A system for publishing messages between nodes.

  - API examples
  - Talk about TCP and UDP multicast transport
  - ETS storage
  """
  import Babble.Utils
  use Babble.Constants

  @typedoc """
  Topics are represented as strings or atoms.

  Topics may be either local (of the form `"my.topic"`) or global (of the form `{:"node@host", "my.topic"}`)
  """
  @type topic :: String.t() | atom() | {node(), String.t()} | {node(), atom()}

  @doc """
  Publish a message to the specified topic.

  `topic` is a String or atom specifying the name of the topic to publish to.

  `message` is a map of key/value pairs, or a keyword list, to publish.

  """
  @spec publish(topic :: topic, message :: map() | keyword()) ::
          :ok | {:error, reason :: String.t()}
  def publish(topic, message) do
    Babble.PubWorker._internal_publish(topic, message)
  end

  @doc """
  Subscribe to a topic.  `topic` can be:
    * A simple string like `"my.topic"`, corresponding to a local topic
    * A `{node, name}` tuple like `{:"node@host", "my.topic"}`, corresponding to a topic
      published by the node `:"node@host"`
    * A wildcard topic like `{:*, "my.topic"}`. This will subscribe to `"my.topic"` published
      by all nodes.

  ## Options

    * `:rate :: float() | :on_publish` - The rate to subscribe to the topic at.

      * If `:rate` is a float, it is interpreted as a rate in Hz.

      * If `:rate` is `:on_publish`, the subscriber will receive every published message.

      * The default is `:on_publish`.

    * `:transport :: :tcp | :udp_multicast` - The transport to use for transmitting remote topics over the network.

      * The default is `:tcp`.

    * `:deliver :: bool()` - Whether to deliver messages to the subscriber process.

      * If `:deliver` is `true`, the subscribing process will receive messages of the form
      `{:babble_msg, {topic_node, topic_name}, message :: map(), timestamp :: float()}` when new topic data arrives.

      * If the topic is remote, a subscription is always required to cause it to be transmitted
      over the network. However, the subscribing process may wish to access the topic data
      using the polling interface rather than having messages delivered to its mailbox.
      In this case, it should call `subscribe` with `:deliver` set to `false`.

      * Calling `subscribe` on a local topic with `:deliver` set to `false` has no effect.

      * The default is `true`.

  """
  @spec subscribe(topic :: topic, options :: keyword()) :: :ok
  def subscribe(topic, options \\ []) do
    id = fn x -> x end
    options = Keyword.update(options, :rate, :on_publish, id)
    options = Keyword.update(options, :transport, :tcp, id)
    options = Keyword.update(options, :deliver, true, id)

    rate = options[:rate]

    if not ((is_number(rate) and rate > 0) or rate === :on_publish) do
      raise ArgumentError, message: ":rate must be a positive number or :on_publish"
    end

    transport = options[:transport]

    if not (transport in [:tcp, :udp_multicast]) do
      raise ArgumentError, message: ":transport must be :tcp or :udp_multicast"
    end

    deliver = options[:deliver]

    if not is_boolean(deliver) do
      raise ArgumentError, message: ":deliver must be a boolean"
    end

    :ok =
      GenServer.call(
        Babble.SubscriptionManager,
        {:subscribe, fully_qualified_topic_name(topic), options}
      )
  end

  @doc """
  Unsubscribe from a topic.
  """
  @spec unsubscribe(topic :: topic) :: :ok
  def unsubscribe(topic) do
    :ok =
      GenServer.call(
        Babble.SubscriptionManager,
        {:unsubscribe, fully_qualified_topic_name(topic)}
      )
  end

  @doc """
  Retrieve the last received values for keys published to the specified topic
  """
  @spec poll(topic :: topic, keys :: list() | :all, stale_time :: float()) ::
          {:ok, list()} | {:error, reason :: String.t()}
  def poll(topic, keys \\ :all, _stale_time \\ :none) do
    try do
      table_vals = topic |> table_name() |> :ets.tab2list() |> Enum.into(%{})

      case keys do
        :all -> {:ok, table_vals}
        l when is_list(l) -> {:ok, for(key <- keys, do: Map.fetch!(table_vals, key))}
      end
    rescue
      # TODO: Give better error messages (topic not found, key not found, topic is stale)
      _ ->
        {:error, "Could not retrieve requested values for topic #{inspect(topic)}"}
    end
  end

  @doc """
  Sets the timesource for topic publication timestamps
  """
  def set_time_source(_time_fun) do
  end
end
