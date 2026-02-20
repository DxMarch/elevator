defmodule Elevator.CabOrders do
  @moduledoc """
  Module responsible for all changes occuring to the cab_order part of the state.
  """
  alias Elevator.Communicator
  use GenServer

  @type state_t :: Elevator.Types.cab_order_map()
  @type floor_t :: Elevator.Types.floor()

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec init(any()) :: {:ok, state_t()}
  def init(_arg \\ []) do
    state = %{Communicator.my_id() => %{version: 0, orders: MapSet.new()}}
    {:ok, state}
  end


  @doc """
  Callback for getting the current cab orders state.
  """
  @spec get_state() :: state_t()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Callback for getting this nodes current cab orders.
  """
  @spec get_my_orders() :: MapSet.t(floor_t())
  def get_my_orders do
    GenServer.call(__MODULE__, :get_my_orders)
  end

  @spec receive_state(state_t()) :: :ok
  def receive_state(other_state) do
    GenServer.cast(__MODULE__, {:receive_state, other_state})
  end

  @spec button_press(floor_t()) :: :noreply
  def button_press(floor) do
    GenServer.cast(__MODULE__, {:button_press, floor})
  end

  @spec arrived_at_floor(floor_t()) :: :ok
  def arrived_at_floor(floor) do
    GenServer.cast(__MODULE__, {:arrived_at_floor, floor})
  end

  # --- Handle calls ---

  def handle_call(:get_my_orders, _from, state) do
    orders = state[Communicator.my_id()].orders
    {:reply, orders, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end


  # --- Handle casts ---

  @spec handle_cast({:receive_state, state_t()}, state_t()) :: {:noreply, state_t()}
  def handle_cast({:receive_state, order_map}, state) do
    new_state = Enum.reduce(order_map, state, fn {node_id, received}, acc ->
      current = Map.get(state, node_id, %{version: 0, orders: MapSet.new()})

      if received[:version] > current[:version] do
        Map.put(acc, node_id, received)
      else
        acc
      end
    end)

    {:noreply, new_state}
  end

  @spec handle_cast({:button_press, floor_t()}, state_t()) :: {:noreply, state_t()}
  def handle_cast({:button_press, floor}, state) do
    new_state = Map.update!(state, Communicator.my_id(), fn %{version: old_version, orders: old_orders} ->
      %{version: old_version + 1, orders: MapSet.put(old_orders, floor)}
    end)
    {:noreply, new_state}
  end

  @spec handle_cast({:arrived_at_floor, floor_t()}, state_t()) :: {:noreply, state_t()}
  def handle_cast({:arrived_at_floor, floor}, state) do
    new_state = Map.update!(state, Communicator.my_id(), fn %{version: old_version, orders: old_orders} ->
      %{version: old_version + 1, orders: MapSet.delete(old_orders, floor)}
    end)
    {:noreply, new_state}
  end
end
