defmodule Elevator.HallOrders do
  @moduledoc """
  Module responsible for all changes occuring to the hall_order part of the state.
  The events that can change hall orders are:
  - Button is pressed.
  - Arrived at floor.
  - Received hall orders from another node.
  - A barrier set gets full, which advances the state.
  """
  alias Elevator.HallOrders.Order
  alias Elevator.HallOrders.Cost
  alias Elevator.Communicator
  require Logger
  use GenServer

  @type hall_button_type :: :hall_down | :hall_up
  @type hall_button :: {Elevator.floor(), hall_button_type()}

  @type cost_map :: %{Node.t() => non_neg_integer()}
  @type hall_order_state ::
          :idle
          | {:pending, MapSet.t()}
          | {:handling, cost_map()}
          | {:arrived, MapSet.t()}

  @type hall_order_map :: %{hall_button() => hall_order_state()}

  @hall_order_refresh_period_ms 1000

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(arg), do: GenServer.start_link(__MODULE__, arg, name: __MODULE__)

  @impl true
  @spec init(any()) :: {:ok, hall_order_map()}
  def init(num_floors) do
    top_floor = num_floors - 1

    # Initialize all orders to idle
    state =
      Range.new(0, top_floor)
      |> Enum.flat_map(fn floor ->
        case floor do
          0 -> [{floor, :hall_up}]
          ^top_floor -> [{floor, :hall_down}]
          _ -> [{floor, :hall_up}, {floor, :hall_down}]
        end
      end)
      |> Enum.map(&{&1, :idle})
      |> Enum.into(%{})

    Process.send_after(self(), :refresh_hall_orders, @hall_order_refresh_period_ms)

    {:ok, state}
  end

  @doc """
  Receives the hall order state from another node and merges it into local state.
  Each order is merged individually using the consensus algorithm in `HallOrders.Order`.
  """
  @spec receive_external(hall_order_map()) :: :ok
  def receive_external(other_order_map),
    do: GenServer.cast(__MODULE__, {:receive_external, other_order_map})

  @doc """
  Places the corresponding order in pending state if it is in idle.
  """
  @spec button_press(Elevator.floor(), hall_button_type()) :: :ok
  def button_press(floor, button_type),
    do: GenServer.cast(__MODULE__, {:button_press, floor, button_type})

  @doc """
  Advances the order to arrived if it is in handling.
  """
  @spec arrived_at_floor(Elevator.floor(), :up | :down) :: :ok
  def arrived_at_floor(floor, direction),
    do: GenServer.cast(__MODULE__, {:arrived_at_floor, floor, direction})

  @doc """
  Retrieve the full hall order state map
  """
  @spec get_order_map() :: hall_order_map()
  def get_order_map(), do: GenServer.call(__MODULE__, :get_order_map)

  @doc """
  Retrieve only the orders we are going to take.
  """
  @spec get_my_orders() :: %{Elevator.floor() => MapSet.t(hall_button_type())}
  def get_my_orders(), do: GenServer.call(__MODULE__, :get_my_orders)

  @doc """
  Get all orders in handling state, in the same format as get_my_orders.
  These are the orders we turn the light on for.
  """
  @spec get_handling_orders() :: %{Elevator.floor() => MapSet.t(hall_button_type())}
  def get_handling_orders(), do: GenServer.call(__MODULE__, :get_handling_orders)

  # Calls --------------------------------------------------

  @impl true
  def handle_call(:get_my_orders, _from, order_map) do
    my_orders = my_orders_from_order_map(order_map)
    {:reply, my_orders, order_map}
  end

  @impl true
  def handle_call(:get_handling_orders, _from, order_map) do
    handling_orders =
      Enum.filter(order_map, &match?({_, {:handling, _}}, &1))
      |> orders_by_floor()

    {:reply, handling_orders, order_map}
  end

  @impl true
  def handle_call(:get_order_map, _, order_map) do
    {:reply, order_map, order_map}
  end

  # Casts --------------------------------------------------

  @impl true
  def handle_cast({:receive_external, other_order_map}, order_map) do
    my_orders = my_orders_from_order_map(order_map)

    new_order_map =
      Map.new(order_map, fn {hall_button, order_state} ->
        new_value =
          Order.update_from_incoming(
            hall_button,
            order_state,
            other_order_map[hall_button],
            my_orders
          )

        {hall_button, new_value}
      end)

    {:noreply, new_order_map, {:continue, :hall_update_state}}
  end

  @impl true
  def handle_cast({:button_press, floor, direction}, order_map) do
    new_order_map = Map.update!(order_map, {floor, direction}, &Order.update_from_button_press/1)
    {:noreply, new_order_map, {:continue, :hall_update_state}}
  end

  @impl true
  def handle_cast({:arrived_at_floor, floor, direction}, order_map) do
    button_type = [up: :hall_up, down: :hall_down][direction]
    hall_button = {floor, button_type}

    new_order_map =
      if Map.has_key?(order_map, hall_button),
        do: Map.update!(order_map, {floor, button_type}, &Order.update_from_arrived_at_floor/1),
        else: order_map

    {:noreply, new_order_map, {:continue, :hall_update_state}}
  end

  @impl true
  def handle_info(:refresh_hall_orders, order_map) do
    Process.send_after(self(), :refresh_hall_orders, @hall_order_refresh_period_ms)
    {:noreply, order_map, {:continue, :hall_update_state}}
  end

  # Continues --------------------------------------------------

  @doc """
  May advance some states, in which case continue is called until convergence.
  """
  @impl true
  def handle_continue(:hall_update_state, order_map) do
    my_orders = my_orders_from_order_map(order_map)

    new_order_map =
      Map.new(order_map, fn {key, order_state} ->
        {key, Order.update_from_barrier_state(key, order_state, my_orders)}
      end)

    {:noreply, new_order_map}
  end

  # Return the orders where we have the lowest cost among serving nodes.
  # Only consider orders where all serving nodes have a cost.
  @spec my_orders_from_order_map(hall_order_map()) :: %{
          Elevator.floor() => MapSet.t(hall_button_type())
        }
  defp my_orders_from_order_map(order_map) do
    who_can_serve = Communicator.who_can_serve()

    Enum.filter(order_map, fn {_, order_state} ->
      with {:handling, cost_map} <- order_state do
        MapSet.subset?(who_can_serve, MapSet.new(Map.keys(cost_map))) and
          Cost.assigned_to_me?(cost_map, who_can_serve)
      else
        _ -> false
      end
    end)
    |> orders_by_floor()
  end

  @type enum_orders ::
          hall_order_map()
          | Enumerable.t({hall_button(), any()})
  @spec orders_by_floor(enum_orders()) :: %{Elevator.floor() => MapSet.t(hall_button_type())}
  defp orders_by_floor(orders) do
    # Restructure order map to the format floor => MapSet(button_type)
    orders
    |> Enum.map(fn {{floor, button_type}, _} -> {floor, button_type} end)
    |> Enum.group_by(fn {floor, _} -> floor end)
    |> Enum.map(fn {floor, order_list} ->
      {floor, MapSet.new(Enum.map(order_list, fn {_, button_type} -> button_type end))}
    end)
    |> Enum.into(%{})
  end
end
