defmodule BabbleTest do
  use ExUnit.Case
  doctest Babble

  test "greets the world" do
    assert Babble.hello() == :world
  end
end
