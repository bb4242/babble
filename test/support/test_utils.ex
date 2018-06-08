defmodule BabbleTest.Utils do
  def echo(listen_topic, response_topic, subscribe_options \\ []) do
    Babble.subscribe({:*, listen_topic}, subscribe_options)

    receive do
      {:babble_msg, {_, ^listen_topic}, msg} ->
        Babble.publish(response_topic, msg)
    end
  end
end
