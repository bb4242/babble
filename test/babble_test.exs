defmodule BabbleTest do
  use ExUnit.Case
  use Babble.Constants

  @topic "test.topic"

  # Run all doctests
  {:ok, modules} = :application.get_key(:babble, :modules)

  for module <- modules do
    doctest module
  end

  test "subscribe input validation" do
    catch_error(Babble.subscribe(@topic, rate: -1))
    catch_error(Babble.subscribe(@topic, rate: -1))
    catch_error(Babble.subscribe(@topic, rate: :nonsense))
    catch_error(Babble.subscribe(@topic, transport: :unknown))
    catch_error(Babble.subscribe(@topic, deliver: :nonsense))
  end

  test "local pub/sub" do
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

  test "get table twice from TableHeir" do
    table = :table_heir_test
    {:ok, table} = Babble.TableHeir.get_table(table)
    :ets.insert(table, key1: 42)
    {:ok, table} = Babble.TableHeir.get_table(table)
    :ets.insert(table, key1: 42)
  end

  test "tables persist after PubWorker dies" do
    :ok = Babble.subscribe(@topic)

    msg = %{key1: [1, 2, 3], key2: 42}
    Babble.publish(@topic, msg)

    fq_topic = Babble.Utils.fully_qualified_topic_name(@topic)
    assert_receive {:babble_msg, ^fq_topic, ^msg}
    {:ok, ^msg} = Babble.poll(@topic)

    # Kill the PubWorker for this topic and make sure the topic data persists
    @topic |> Babble.Utils.table_name() |> Process.whereis() |> Process.exit(:kill)
    Process.sleep(500)
    {:ok, ^msg} = Babble.poll(@topic)
  end

  @topic1 "test.remote.topic1"
  @topic2 "test.remote.topic2"
  @slaves [:"test-slave1@127.0.0.1", :"test-slave2@127.0.0.1", :"test-slave3@127.0.0.1"]

  @tag :cluster
  test "cluster pub/sub" do
    # Subscribe to topics by node individually
    for slave <- @slaves do
      Babble.subscribe({slave, @topic1})
    end

    # Subscribe to wildcard topic
    Babble.subscribe({:*, @topic2})

    # Start the slave after subscribing so that we test subscription synchronization
    # on node connection
    :ok = :net_kernel.monitor_nodes(true)

    for slave <- @slaves do
      Task.start_link(fn ->
        System.cmd(
          "elixir",
          "--name #{Atom.to_string(slave)} --cookie #{Atom.to_string(Node.get_cookie())} -S mix run --no-halt"
          |> String.split(" "),
          env: [{"MIX_ENV", "test"}]
        )
      end)

      on_exit(fn -> :slave.stop(slave) end)
    end

    for slave <- @slaves do
      assert_receive {:nodeup, ^slave}, 5000
    end

    # Allow subscription tables to synchronize
    Process.sleep(500)

    for slave <- @slaves do
      msg1 = %{key1: :val1, key2: :val2}
      msg2 = %{key1: 1, key2: 2}
      :ok = :rpc.call(slave, Babble, :publish, [@topic1, msg1])
      :ok = :rpc.call(slave, Babble, :publish, [@topic2, msg2])

      fq_topic1 = {slave, @topic1}
      fq_topic2 = {slave, @topic2}
      assert_receive {:babble_msg, ^fq_topic1, ^msg1}
      assert_receive {:babble_msg, ^fq_topic2, ^msg2}
      {:ok, ^msg1} = Babble.poll(fq_topic1)
      {:ok, ^msg2} = Babble.poll(fq_topic2)

      # Make sure remote tables don't disappear if the PubWorker dies
      fq_topic1 |> Babble.Utils.table_name() |> Process.whereis() |> Process.exit(:kill)
      Process.sleep(100)
      {:ok, ^msg1} = Babble.poll(fq_topic1)

      # Test that the remote topic gets cleaned up after node disconnection
      :ok = :rpc.call(slave, :init, :stop, [])
      assert_receive {:nodedown, ^slave}, 5000
      assert_receive {:babble_remote_topic_disconnect, ^fq_topic1}
      assert_receive {:babble_remote_topic_disconnect, ^fq_topic2}
      Process.sleep(100)
      {:error, _} = Babble.poll(fq_topic1)
      {:error, _} = Babble.poll(fq_topic2)
    end
  end
end
