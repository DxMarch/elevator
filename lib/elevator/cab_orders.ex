defmodule Elevator.CabOrders do
  @moduledoc """
  Module responsible for all changes occuring to the cab_order part of the state.
  """
  use GenServer

  @type cab_order_map :: Elevator.Types.cab_order_map()
  @type floor :: Elevator.Types.floor()

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  @spec init(any()) :: {:ok, cab_order_map()}
  def init(_arg \\ []) do
    state = %{Node.self() => %{version: 0, orders: MapSet.new()}}
    {:ok, state}
  end

  # User API --------------------------------------------------

  @spec get_order_map() :: cab_order_map()
  def get_order_map, do: GenServer.call(__MODULE__, :get_order_map)

  @doc """
  Retrieve *this* node's current cab orders.
  """
  @spec get_my_orders() :: MapSet.t(floor())
  def get_my_orders, do: GenServer.call(__MODULE__, :get_my_orders)

  @doc """
  Receive cab order information from another node.
  Maps are merged according to highest version numbers.
  """
  @spec receive_external(cab_order_map()) :: :ok
  def receive_external(other_order_map),
    do: GenServer.cast(__MODULE__, {:receive_external, other_order_map})

  @doc """
  Add a cab order and increment our own version number.
  """
  @spec button_press(floor()) :: :ok
  def button_press(floor), do: GenServer.cast(__MODULE__, {:button_press, floor})

  @doc """
  Remove a cab order and increment our own version number.
  """
  @spec arrived_at_floor(floor()) :: :ok
  def arrived_at_floor(floor), do: GenServer.cast(__MODULE__, {:arrived_at_floor, floor})

  # Calls --------------------------------------------------
  @impl true
  def handle_call(:get_my_orders, _from, order_map) do
    orders = order_map[Node.self()].orders
    {:reply, orders, order_map}
  end

  @impl true
  def handle_call(:get_order_map, _from, order_map) do
    {:reply, order_map, order_map}
  end

  # Casts --------------------------------------------------

  @impl true
  @spec handle_cast({:receive_external, cab_order_map()}, cab_order_map()) ::
          {:noreply, cab_order_map()}
  def handle_cast({:receive_external, other_order_map}, order_map) do
    new_order_map =
      Map.merge(order_map, other_order_map, fn _, current, received ->
        if received.version > current.version,
          do: received,
          else: current
      end)

    {:noreply, new_order_map}
  end

  @impl true
  @spec handle_cast({:button_press, floor()}, cab_order_map()) :: {:noreply, cab_order_map()}
  def handle_cast({:button_press, floor}, order_map) do
    new_order_map =
      Map.update!(order_map, Node.self(), fn %{version: old_version, orders: old_orders} ->
        %{version: old_version + 1, orders: MapSet.put(old_orders, floor)}
      end)

    {:noreply, new_order_map}
  end

  @impl true
  @spec handle_cast({:arrived_at_floor, floor()}, cab_order_map()) :: {:noreply, cab_order_map()}
  def handle_cast({:arrived_at_floor, floor}, order_map) do
    new_order_map =
      Map.update!(order_map, Node.self(), fn %{version: old_version, orders: old_orders} ->
        %{version: old_version + 1, orders: MapSet.delete(old_orders, floor)}
      end)

    {:noreply, new_order_map}
  end
end
