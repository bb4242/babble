defmodule Babble do
  @moduledoc """
  A system for publishing messages between nodes.

  - API examples
  - Talk about TCP and UDP multicast transport
  - ETS storage
  """

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
    # TODO: Move all of this logic into a separate asynchronous Task process linked to the caller pcoess

    fq_topic = fully_qualified_topic_name(topic)
    owner = :ets.info(fq_topic, :owner)

    if owner == :undefined do
      # Need to create the table, then publish
      ^fq_topic = :ets.new(fq_topic, [:named_table, :public, :set])
    end

    # Insert values into local ETS table
    vals =
      if is_map(message) do
        Map.to_list(message)
      else
        message
      end

    :ets.insert(fq_topic, vals)

    # Lookup subscribers and deliver message to them

    :ok
  end

  @doc """
  Subscribe to a topic.

  ## Options

    * `:rate :: float() | :on_publish` - The rate to subscribe to the topic at.

      * If `:rate` is a float, it is interpreted as a rate in Hz. If the topic is remote,
      it will be transmitted over the network via UDP multicast. This is appropriate
      for topics that are published at regular intervals, such as periodic sensor readings.

      * If `:rate` is `:on_publish`, the subscriber will receive every published message.
      If the topic is remote, it will be transmitted over the network via
      TCP, which is a reliable transport. This is appropriate for topics that are
      published only intermittently, such as configuration data.

      * The default is `:on_publish`.

    * `:deliver :: bool()` - Whether to deliver messages to the subscriber process.

      * If `:deliver` is `true`, the subscribing process will receive messages of the form
      `{:babble_msg, topic :: topic, message :: map(), timestamp :: float()}` when new topic data arrives.

      * If the topic is remote, a subscription is always required to cause it to be transmitted
      over the network. However, the subscribing process may wish to access the topic data
      using the polling interface rather than having messages delivered to its mailbox.
      In this case, it should call `subscribe` with `:deliver` set to `false`.

      * Calling `subscribe` on a local topic with `:deliver` set to `false` has no effect.

      * The default is `true`.

  """
  @spec subscribe(topic :: topic, options :: keyword()) :: :ok
  def subscribe(topic, options \\ []) do
    :ok
  end

  @doc """
  Unsubscribe from a topic.
  """
  @spec unsubscribe(topic :: topic) :: :ok
  def unsubscribe(topic) do
    :ok
  end

  @doc """
  Retrieve the last received values for keys published to the specified topic
  """
  @spec poll(topic :: topic, keys :: list() | :all, stale_time :: float()) ::
          {:ok, list()} | {:error, reason :: String.t()}
  def poll(topic, keys \\ :all, stale_time \\ :none) do
    table_map = Enum.into(:ets.tab2list(fully_qualified_topic_name(topic)), %{})
    case keys do
      :all -> table_map
      l when is_list(l) -> for(key <- keys, into: %{}, do: {key, Map.fetch!(table_map, key)})
    end
  end

  @doc """
  Sets the timesource for topic publication timestamps
  """
  def set_time_source(time_fun) do
  end

  ### Helper functions

  @doc """
  Get the fully qualified name for a given topic, as an atom

  ## Examples
  ```
     iex> Babble.fully_qualified_topic_name({:"node@host", "my.topic"})
     :"node@host/my.topic"
  ```
  """
  @spec fully_qualified_topic_name(topic) :: atom()
  def fully_qualified_topic_name({node, topic}) when is_atom(node) do
    String.to_atom("#{node}/#{topic}")
  end

  def fully_qualified_topic_name(topic) when is_atom(topic) or is_binary(topic) do
    if String.contains?(Atom.to_string(topic), "/") do
      topic
    else
      String.to_atom("#{Node.self()}/#{topic}")
    end
  end
end
