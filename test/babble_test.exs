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
end
