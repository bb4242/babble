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

  `message` is a map of key/value pairs to publish.

  """
  @spec publish(topic :: topic, message :: map()) :: :ok | {:error, reason :: String.t()}
  def publish(topic, message) do
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
  def poll(topic, keys \\ [], stale_time \\ :none) do
    {:ok, []}
  end

  @doc """
  Sets the timesource for topic publication timestamps
  """
  def set_time_source(time_fun) do
  end
end
