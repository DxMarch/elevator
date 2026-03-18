defmodule Elevator.HallOrders do
  @moduledoc """
  Module responsible for all changes occuring to the hall_order part of the state.
  The events that can change hall orders are:
  - Button is pressed.
  - Arrived at floor.
  - Received hall orders from another node.
  """
  alias Elevator.HallOrders.Order
  alias Elevator.HallOrders.Cost
  alias Elevator.Communicator
  require Logger
  use GenServer

  @type hall_order_map :: Elevator.Types.hall_order_map()
  @type floor :: Elevator.Types.floor()
  @type hall_btn :: Elevator.Types.hall_btn()

  @hall_order_refresh_period_ms 1000

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  @spec init(any()) :: {:ok, hall_order_map()}
  def init(num_floors) do
    top_floor = num_floors - 1

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
  @spec button_press(floor(), hall_btn()) :: :ok
  def button_press(floor, button_type),
    do: GenServer.cast(__MODULE__, {:button_press, floor, button_type})

  @doc """
  Goes back to idle if the order is confirmed.
  """
  @spec arrived_at_floor(floor(), :up | :down) :: :ok
  def arrived_at_floor(floor, direction) do
    GenServer.cast(__MODULE__, {:arrived_at_floor, floor, direction})
  end

  @doc """
  Retrieve the full hall order state map
  """
  @spec get_state() :: hall_order_map()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @doc """
  Retrieve only the orders we are going to take.
  """
  @spec get_my_orders() :: %{Elevator.Types.floor() => MapSet.t(Elevator.Types.hall_btn())}
  def get_my_orders do
    GenServer.call(__MODULE__, :get_my_orders)
  end

  @doc """
  Get all confirmed orders in same format as get_my_orders.
  These are the orders we turn the light on for.
  """
  @spec get_confirmed_orders() :: %{Elevator.Types.floor() => MapSet.t(Elevator.Types.hall_btn())}
  def get_confirmed_orders do
    GenServer.call(__MODULE__, :get_confirmed_orders)
  end

  # Calls --------------------------------------------------

  @impl true
  def handle_call(:get_my_orders, _from, order_map) do
    alive = Communicator.who_can_serve()

    my_orders = my_orders_from_order_map(order_map, alive)
    {:reply, my_orders, order_map}
  end

  @impl true
  def handle_call(:get_confirmed_orders, _from, order_map) do
    confirmed_orders =
      Enum.filter(order_map, fn {_, order_state} ->
        case order_state do
          {:handling, _} -> true
          _ -> false
        end
      end)
      |> orders_by_floor()

    {:reply, confirmed_orders, order_map}
  end

  @impl true
  def handle_call(:get_state, _, order_map) do
    {:reply, order_map, order_map}
  end

  # Casts --------------------------------------------------

  @impl true
  @spec handle_cast({:receive_external, hall_order_map()}, hall_order_map()) ::
          {:noreply, hall_order_map(), {:continue, :hall_update_state}}
  def handle_cast({:receive_external, other_order_map}, order_map) do
    who_can_serve = Communicator.who_can_serve()
    my_orders = my_orders_from_order_map(order_map, who_can_serve)

    new_order_map =
      Map.keys(order_map)
      |> Enum.map(fn key ->
        new_value = Order.merge_hall_orders(key, order_map[key], other_order_map[key], my_orders)
        {key, new_value}
      end)
      |> Enum.into(%{})

    {:noreply, new_order_map, {:continue, :hall_update_state}}
  end

  @impl true
  @spec handle_cast({:button_press, floor(), hall_btn()}, hall_order_map()) ::
          {:noreply, hall_order_map(), {:continue, :hall_update_state}}
  def handle_cast({:button_press, floor, direction}, order_map) do
    # If in idle, go to pending. Otherwise, ignore.
    key = {floor, direction}

    old_order_state = order_map[key]

    new_order_map =
      case old_order_state do
        :idle ->
          Map.put(order_map, key, {:pending, MapSet.new([Node.self()])})

        _ ->
          order_map
      end

    new_order_state = new_order_map[key]

    if old_order_state != new_order_state do
      Logger.debug(fn ->
        "hall_button_press floor=#{floor} button=#{direction} from=#{inspect(old_order_state)} to=#{inspect(new_order_state)}"
      end)
    end

    {:noreply, new_order_map, {:continue, :hall_update_state}}
  end

  @impl true
  def handle_cast({:arrived_at_floor, floor, direction}, order_map) do
    # TODO: Find out if barrier set should be full as well?
    button_type = [up: :hall_up, down: :hall_down][direction]
    key = {floor, button_type}
    order_state = order_map[key]

    new_order_map =
      case order_state do
        {:handling, _} ->
          Map.put(order_map, key, {:arrived, MapSet.new([Node.self()])})

        _ ->
          order_map
      end

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
  @spec handle_continue(:hall_update_state, hall_order_map()) ::
          {:noreply, hall_order_map()}
          | {:noreply, hall_order_map(), {:continue, :hall_update_state}}
  def handle_continue(:hall_update_state, order_map) do
    alive = Communicator.who_can_serve()
    my_orders = my_orders_from_order_map(order_map, alive)

    {any_did_change, new_order_map} =
      Enum.reduce(order_map, {false, %{}}, fn {key, button_state},
                                              {acc_did_change, acc_order_map} ->
        {did_change, new_button_state} = Order.update_hall_order(key, button_state, my_orders)

        {acc_did_change or did_change, Map.put(acc_order_map, key, new_button_state)}
      end)

    if any_did_change do
      {:noreply, new_order_map, {:continue, :hall_update_state}}
    else
      {:noreply, new_order_map}
    end
  end

  defp my_orders_from_order_map(order_map, alive) do
    Enum.filter(order_map, fn {_, order_state} ->
      case order_state do
        {:handling, cost_map} ->
          if Cost.min_alive_cost(cost_map, alive) == Node.self() do
            Logger.debug(
              "\nCost map: #{inspect(cost_map)}\nAlive: #{inspect(alive)}\nI (#{inspect(Node.self())}) am the one to serve"
            )
          end

          Cost.min_alive_cost(cost_map, alive) == Node.self()

        _ ->
          false
      end
    end)
    |> orders_by_floor()
  end

  @type enum_orders ::
          Elevator.Types.hall_order_map()
          | Enumerable.t({Elevator.Types.hall_order_key(), Elevator.Types.hall_order_state()})
  @spec orders_by_floor(enum_orders()) :: %{floor() => MapSet.t(hall_btn())}
  defp orders_by_floor(orders) do
    # Restructure order map to the format floor => MapSet(order)
    orders
    |> Enum.map(fn {{floor, btn_type}, _} -> {floor, btn_type} end)
    |> Enum.group_by(fn {floor, _} -> floor end)
    |> Enum.map(fn {floor, order_list} ->
      {floor, MapSet.new(Enum.map(order_list, fn {_, btn_type} -> btn_type end))}
    end)
    |> Enum.into(%{})
  end
end
