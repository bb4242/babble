defmodule BabbleTest.Utils do
  def echo(listen_topic, response_topic) do
    Babble.subscribe({:*, listen_topic})

    receive do
      {:babble_msg, {_, ^listen_topic}, msg} ->
        Babble.publish(response_topic, msg)
    end
  end
end
