defmodule BabbleTest do
  use ExUnit.Case

  @topic "test.topic"

  # Run all doctests
  {:ok, modules} = :application.get_key(:babble, :modules)

  for module <- modules do
    doctest module
  end

  test "local pub/sub" do
    catch_error(Babble.subscribe(@topic, rate: -1))
    catch_error(Babble.subscribe(@topic, rate: -1))
    catch_error(Babble.subscribe(@topic, rate: :nonsense))
    catch_error(Babble.subscribe(@topic, transport: :unknown))
    catch_error(Babble.subscribe(@topic, deliver: :nonsense))

    :ok = Babble.subscribe(@topic)

    msg = %{key1: :val1, key2: :val2}
    :ok = Babble.publish(@topic, msg)

    fq_topic = Babble.Utils.fully_qualified_topic_name(@topic)
    assert_receive {:babble_msg, ^fq_topic, ^msg}

    {:ok, ^msg} = Babble.poll(@topic)
  end

  test "local unsubscribe" do
    :ok = Babble.subscribe(@topic)
    :ok = Babble.subscribe(@topic)
    :ok = Babble.unsubscribe(@topic)

    msg = %{key1: :val1, key2: :val2}
    :ok = Babble.publish(@topic, msg)
    refute_receive _
  end

  @topic "test.remote.topic"

  test "cluster pub/sub" do
    slave = :"slave1@127.0.0.1"
    Babble.subscribe({slave, @topic})

    # Start the slave after subscribing so that we test subscription synchronization
    # on node connection
    Port.open({:spawn, "elixir --name #{Atom.to_string(slave)} -S mix run --no-halt"}, [])

    # TODO: Eventually switch to libcluster and wait for slave to connect
    Process.sleep(3000)
    :pong = Node.ping(slave)
    Process.sleep(1000)

    msg = %{key1: :val1, key2: :val2}
    :ok = :rpc.call(slave, Babble, :publish, [@topic, msg])

    fq_topic = Babble.Utils.fully_qualified_topic_name({slave, @topic})
    assert_receive {:babble_msg, ^fq_topic, ^msg}
    {:ok, ^msg} = Babble.poll(fq_topic)

    # Test that the remote topic gets cleaned up after node disconnection
    :slave.stop(slave)
    assert_receive {:babble_remote_topic_disconnect, ^fq_topic}
    Process.sleep(500)
    {:error, _} = Babble.poll(fq_topic)

    # Make sure we shut down the node
    # TODO: Wrap the Port.open call in a wrapper to prevent zombie processes
    # https://hexdocs.pm/elixir/Port.html#module-zombie-processes
    :rpc.cast(slave, :init, :stop, [])
  end
end
