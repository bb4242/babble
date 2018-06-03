defmodule Babble.Constants do
  @moduledoc false

  defmacro __using__(_) do
    quote do
      @subscription_topic "babble.subscriptions"
    end
  end
end
