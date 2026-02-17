defmodule Elevator.CabOrders do
  @moduledoc """
  Module responsible for all changes occuring to the cab_order part of the state.
  """

  use GenServer

  alias Elevator.Types
  @type state :: Types.cab_order_map()
  @type node_val :: Types.cab_orders_snapshot()

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    node_val = %{version: 0, orders: MapSet.new()}
    state = %{node() => node_val}
    {:ok, state}
  end

  # User API ---------------------------------------------------------

  @doc """
  Call when a cab button is pressed,
  add it to the set and return the full set
  """
  @spec add(Types.floor()) :: MapSet.t()
  def add(floor) do
    GenServer.call(__MODULE__, {:add_order, floor})
  end

  @doc """
  Call to remove orders
  """
  @spec remove(Types.floor()) :: :ok
  def remove(floor) do
    GenServer.cast(__MODULE__, {:remove_order, floor})
  end

  # Calls ------------------------------------------------------------

  @impl true
  def handle_call({:add_order, floor}, _from, state) do
    new_state =
      update_in(
        state[node()].orders,
        fn set -> MapSet.put(set || MapSet.new(), floor) end
      )

    orders = get_in(new_state, [node(), :orders])
    {:reply, orders, new_state}
  end

  # Casts ------------------------------------------------------------

  @impl true
  def handle_cast({:remove_order, floor}, state) do
    new_state =
      update_in(state[node()].orders, fn set -> MapSet.delete(set || MapSet.new(), floor) end)
      |> then(fn s -> update_in(s[node()].version, &(&1 + 1)) end)

    {:noreply, new_state}
  end
end
