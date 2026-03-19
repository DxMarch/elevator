defmodule Elevator.HallOrders.Simulation do
  @moduledoc """
  Pure hall-order cost simulation.
  """

  alias Elevator.Decision
  alias Elevator.FSM.State

  @travel_duration_ms 2500
  @max_simulation_steps 256
  @unreachable_cost 30000

  @type floor :: Elevator.floor()
  @type hall_button_type :: Elevator.HallOrders.hall_button_type()
  @type combined_order_map :: Elevator.combined_order_map()

  defmodule SimState do
    @enforce_keys [:orders, :elevator_state, :target, :time_ms, :steps_left]
    defstruct [:orders, :elevator_state, :target, :time_ms, :steps_left]
  end

  @type simulation :: %SimState{
          orders: combined_order_map(),
          elevator_state: State.t(),
          target: {floor(), hall_button_type()},
          time_ms: non_neg_integer(),
          steps_left: non_neg_integer()
        }

  @spec travel_duration_ms() :: non_neg_integer()
  def travel_duration_ms, do: @travel_duration_ms

  @spec unreachable_cost() :: non_neg_integer()
  def unreachable_cost, do: @unreachable_cost

  @spec initial_time_ms(State.t(), floor()) :: number()
  def initial_time_ms(elevator_state, target_floor) do
    cond do
      elevator_state.behavior == :door_open and target_floor != elevator_state.floor ->
        Elevator.door_open_duration_ms() / 2

      elevator_state.behavior == :moving ->
        @travel_duration_ms / 2

      true ->
        0
    end
  end

  @spec simulate_time_until_served(combined_order_map(), State.t(), {floor(), hall_button_type()}) ::
          non_neg_integer()
  def simulate_time_until_served(_orders, %{floor: :unknown}, _target),
    do: @unreachable_cost

  def simulate_time_until_served(_orders, %{obstructed: true}, _target),
    do: @unreachable_cost

  def simulate_time_until_served(orders, elevator_state, target) do
    initial_time_ms = initial_time_ms(elevator_state, elem(target, 0))

    if target_cleared?(orders, target) do
      0
    else
      sim_state = %SimState{
        orders: orders,
        elevator_state: elevator_state,
        target: target,
        time_ms: initial_time_ms,
        steps_left: @max_simulation_steps
      }

      do_simulate(sim_state)
    end
  end

  @spec do_simulate(simulation()) :: non_neg_integer()
  defp do_simulate(%SimState{steps_left: 0}), do: @unreachable_cost

  defp do_simulate(%SimState{orders: orders, target: target, time_ms: time_ms} = sim_state) do
    if target_cleared?(orders, target) do
      time_ms
    else
      do_simulate_step(sim_state)
    end
  end

  @spec do_simulate_step(simulation()) :: non_neg_integer()
  defp do_simulate_step(%SimState{orders: orders, elevator_state: elevator_state} = sim_state) do
    {direction, behavior} = Decision.next_action(orders, elevator_state)

    {next_orders, next_elevator_state, delta_ms} =
      case behavior do
        :idle ->
          raise(
            "Invalid simulation transition: got :idle while target still pending. sim_state=#{inspect(sim_state)}"
          )

        :moving ->
          {:ok, next_floor} = move_one_floor(elevator_state.floor, direction)

          {orders,
           %{
             elevator_state
             | floor: next_floor,
               between_floors: false,
               direction: direction,
               behavior: :moving
           }, @travel_duration_ms}

        :door_open ->
          {clear_requests_at_floor_in_direction(orders, elevator_state.floor, direction),
           %{
             elevator_state
             | direction: direction,
               behavior: :idle,
               between_floors: false
           }, Elevator.door_open_duration_ms()}
      end

    next_sim_state = %SimState{
      sim_state
      | orders: next_orders,
        elevator_state: next_elevator_state,
        time_ms: sim_state.time_ms + delta_ms,
        steps_left: sim_state.steps_left - 1
    }

    do_simulate(next_sim_state)
  end

  defp target_cleared?(orders, {floor, hall_button_type}) do
    orders
    |> Map.get(floor, MapSet.new())
    |> MapSet.member?(hall_button_type)
    |> Kernel.not()
  end

  defp move_one_floor(floor, :up) do
    if floor < Elevator.num_floors() - 1,
      do: {:ok, floor + 1},
      else: raise("Invalid simulation transition: cannot move up from floor #{inspect(floor)}")
  end

  defp move_one_floor(floor, :down) do
    if floor > 0,
      do: {:ok, floor - 1},
      else: raise("Invalid simulation transition: cannot move down from floor #{inspect(floor)}")
  end

  defp clear_requests_at_floor_in_direction(orders, floor, direction) do
    floor_orders_after_cab_clear =
      orders
      |> Map.get(floor, MapSet.new())
      |> MapSet.delete(:cab)

    remaining_floor_orders =
      case direction do
        :up -> MapSet.delete(floor_orders_after_cab_clear, :hall_up)
        :down -> MapSet.delete(floor_orders_after_cab_clear, :hall_down)
      end

    if MapSet.size(remaining_floor_orders) == 0,
      do: Map.delete(orders, floor),
      else: Map.put(orders, floor, remaining_floor_orders)
  end
end
