defmodule BabbleTest do
  use ExUnit.Case
  use Babble.Constants

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

    fq_topic = {Node.self(), @topic}
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
  @slaves [:"test-slave1@127.0.01", :"test-slave2@127.0.01", :"test-slave3@127.0.01"]

  @tag :cluster
  test "cluster pub/sub" do
    for slave <- @slaves do
      # TODO: subscribe to all_nodes topic
      Babble.subscribe({slave, @topic})
    end

    # Start the slave after subscribing so that we test subscription synchronization
    # on node connection
    :ok = :net_kernel.monitor_nodes(true)

    for slave <- @slaves do
      Port.open(
        {:spawn,
         "elixir --name #{Atom.to_string(slave)} --cookie #{Atom.to_string(Node.get_cookie())} -S mix run --no-halt"},
        [{:env, [{'MIX_ENV', 'test'}]}]
      )
    end

    for slave <- @slaves do
      assert_receive {:nodeup, ^slave}, 5000
      on_exit(fn -> :slave.stop(slave) end)
    end

    for slave <- @slaves do
      msg = %{key1: :val1, key2: :val2}
      :ok = :rpc.call(slave, Babble, :publish, [@topic, msg])

      fq_topic = {slave, @topic}
      assert_receive {:babble_msg, ^fq_topic, ^msg}
      {:ok, ^msg} = Babble.poll(fq_topic)

      # Test that the remote topic gets cleaned up after node disconnection
      :slave.stop(slave)
      assert_receive {:babble_remote_topic_disconnect, ^fq_topic}
      Process.sleep(500)
      {:error, _} = Babble.poll(fq_topic)
    end

    # Make sure we shut down the node
    # TODO: Wrap the Port.open call in a wrapper to prevent zombie processes
    # https://hexdocs.pm/elixir/Port.html#module-zombie-processes
  end
end
