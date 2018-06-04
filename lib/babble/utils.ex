defmodule Babble.Utils do
  @moduledoc "Babble utility functions"

  @doc """
  Get the fully qualified name for a given topic

  ## Examples

  ```
  iex> Babble.Utils.fully_qualified_topic_name({:"node@host", "my.topic"})
  {:"node@host", "my.topic"}

  iex> Babble.Utils.fully_qualified_topic_name(:"node@host:my.topic")
  {:"node@host", "my.topic"}

  iex> Babble.Utils.fully_qualified_topic_name("node@host:my.topic")
  {:"node@host", "my.topic"}
  ```
  """
  @spec fully_qualified_topic_name(Babble.topic()) :: atom()
  def fully_qualified_topic_name({node, topic}) when is_atom(node) and is_binary(topic) do
    {node, topic}
  end

  def fully_qualified_topic_name(topic) when is_atom(topic) do
    fully_qualified_topic_name(Atom.to_string(topic))
  end

  def fully_qualified_topic_name(topic) when is_binary(topic) do
    if String.contains?(topic, ":") do
      [node, local_name] = String.split(topic, ":")
      {String.to_atom(node), local_name}
    else
      {Node.self(), topic}
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
    {node, _} = fully_qualified_topic_name(topic)
    node
  end

  @doc """
  Get the ETS table name for the given topic

  ```
  iex> Babble.Utils.table_name(:"node@host:my.topic")
  :"Babble:node@host:my.topic"

  """
  def table_name(topic) do
    {node, local_name} = fully_qualified_topic_name(topic)
    String.to_atom("Babble:" <> Atom.to_string(node) <> ":" <> local_name)
  end
end
