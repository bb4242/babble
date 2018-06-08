defmodule Babble.Transports.RemotePublisher do
  @moduledoc """
  Receives incoming publication messages from other nodes and publishes them to local subscribers
  """

  use GenServer

  @udp_message_id 1

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def remote_publish(remote_node, topic, message, transport = :tcp, now, pub_time_table, all_subs) do
    send({__MODULE__, remote_node}, {:p, topic, message})

    for {sub_pid, %{rate: rate, transport: ^transport}} <- all_subs,
        is_number(rate),
        node(sub_pid) == remote_node do
      update_pub_time(pub_time_table, sub_pid, now, rate)
    end
  end

  def remote_publish(_node, topic, message, transport = :udp, now, pub_time_table, all_subs) do
    Babble.Transports.UdpMulticast.send(@udp_message_id, {:p, topic, message})

    for {sub_pid, %{rate: rate, transport: ^transport}} <- all_subs,
        is_number(rate),
        node(sub_pid) != node() do
      update_pub_time(pub_time_table, sub_pid, now, rate)
    end
  end

  @impl true
  def init(_opts) do
    {:ok, _} = Babble.Transports.UdpMulticast.register_listener(@udp_message_id)
    {:ok, []}
  end

  @impl true
  def handle_info({:p, fq_topic = {origin_node, _topic_name}, message}, state) do
    if Node.self() != origin_node do
      Babble.PubWorker._internal_publish(fq_topic, message, remote_publish: false)
    end

    {:noreply, state}
  end

  def update_pub_time(pub_time_table, sub_pid, now, rate) do
    :ets.insert(pub_time_table, [{sub_pid, now + 1000 / rate}])
  end

  def update_pub_time(pub_time_table, sub_pid, now) do
    :ets.insert(pub_time_table, [{sub_pid, now}])
  end
end
