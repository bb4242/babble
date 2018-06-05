defmodule Babble.TableHeir do
  @moduledoc """
  A simple process that serves as the heir to all ETS topic tables, preventing
  them from disappearing if their `Babble.PubWorker` process terminates
  """
  use GenServer

  # Client API
  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc """
  Transfer ownership of the given table to the caller, creating it if necessary.
  The #{__MODULE__} process will be the heir of the table if `set_heir = true`
  """
  def get_table(table_name, set_heir \\ true) do
    case GenServer.call(__MODULE__, {:get_table, table_name, set_heir}) do
      :transferred ->
        server_pid = Process.whereis(__MODULE__)

        receive do
          {:"ETS-TRANSFER", _table_ref, ^server_pid, []} -> {:ok, table_name}
        after
          1000 ->
            {:error, "Could not get table"}
        end

      :already_exists ->
        {:ok, table_name}
    end
  end

  # Server callbacks
  @impl true
  def init([]) do
    {:ok, []}
  end

  @impl true
  def handle_call({:get_table, table_name, set_heir}, {pid, _tag}, state) do
    case :ets.info(table_name) do
      :undefined ->
        heir_opt =
          if set_heir do
            [{:heir, self(), []}]
          else
            []
          end

        ets_new_opts = [:named_table, :protected, :set] ++ heir_opt
        _table = :ets.new(table_name, ets_new_opts)
        :ets.give_away(table_name, pid, [])
        {:reply, :transferred, state}

      info ->
        if info[:owner] == self() do
          :ets.give_away(table_name, pid, [])
          {:reply, :transferred, state}
        else
          {:reply, :already_exists, state}
        end
    end
  end

  @impl true
  def handle_info({:"ETS-TRANSFER", _, _, _}, state) do
    {:noreply, state}
  end
end
