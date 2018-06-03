defmodule Babble.Utils do
  @moduledoc "Babble utility functions"

  @doc """
  Get the fully qualified name for a given topic, as an atom

  ## Examples

  ```
  iex> Babble.Utils.fully_qualified_topic_name({:"node@host", "my.topic"})
  :"node@host:my.topic"

  iex> Babble.Utils.fully_qualified_topic_name(:"node@host:my.topic")
  :"node@host:my.topic"
  ```
  """
  @spec fully_qualified_topic_name(Babble.topic()) :: atom()
  def fully_qualified_topic_name({node, topic}) when is_atom(node) do
    String.to_atom("#{node}:#{topic}")
  end

  def fully_qualified_topic_name(topic) when is_atom(topic) do
    fully_qualified_topic_name(Atom.to_string(topic))
  end

  def fully_qualified_topic_name(topic) when is_binary(topic) do
    if String.contains?(topic, ":") do
      String.to_atom(topic)
    else
      String.to_atom("#{Node.self()}:#{topic}")
    end
  end

  @doc """
  Get the node for the specified topic

  ```
  iex> Babble.Utils.get_topic_node(:"node@host:my.topic")
  :"node@host"
  ```
  """
  def get_topic_node(topic) do
    topic
    |> fully_qualified_topic_name
    |> Atom.to_string()
    |> String.split(":")
    |> Enum.at(0)
    |> String.to_atom()
  end
end
