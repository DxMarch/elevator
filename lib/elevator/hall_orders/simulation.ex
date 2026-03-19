defmodule Elevator.HallOrders.Simulation do
  @moduledoc """
  Pure hall-order cost simulation.
  """

  alias Elevator.HallOrders
  alias Elevator.OrderUtils
  alias Elevator.FSM.State
  alias Elevator.FSM.Transition

  @travel_duration_ms 2500
  @max_simulation_steps 256
  @unreachable_cost 30000

  defmodule SimState do
    @enforce_keys [:orders, :elevator_state, :target, :time_ms, :steps_left]
    defstruct [:orders, :elevator_state, :target, :time_ms, :steps_left]
  end

  @type simulation :: %SimState{
          orders: OrderUtils.combined_order_map(),
          elevator_state: State.t(),
          target: {Elevator.floor(), HallOrders.hall_button_type()},
          time_ms: non_neg_integer(),
          steps_left: non_neg_integer()
        }

  @spec travel_duration_ms() :: non_neg_integer()
  def travel_duration_ms, do: @travel_duration_ms

  @spec unreachable_cost() :: non_neg_integer()
  def unreachable_cost, do: @unreachable_cost

  @spec initial_time_ms(State.t(), Elevator.floor()) :: non_neg_integer()
  def initial_time_ms(elevator_state, target_floor) do
    cond do
      elevator_state.behavior == :door_open and target_floor != elevator_state.floor ->
        div(Elevator.door_open_duration_ms(), 2)

      elevator_state.behavior == :moving ->
        div(@travel_duration_ms, 2)

      true ->
        0
    end
  end

  @spec simulate_time_until_served(
          OrderUtils.combined_order_map(),
          State.t(),
          {Elevator.floor(), HallOrders.hall_button_type()}
        ) ::
          non_neg_integer()
  def simulate_time_until_served(_orders, %{floor: :unknown} = _elevator_state, _target),
    do: @unreachable_cost

  def simulate_time_until_served(_orders, %{obstructed: true} = _elevator_state, _target),
    do: @unreachable_cost

  def simulate_time_until_served(orders, elevator_state, target) do
    initial_time_ms = initial_time_ms(elevator_state, elem(target, 0))

    sim_state = %SimState{
      orders: orders,
      elevator_state: elevator_state,
      target: target,
      time_ms: initial_time_ms,
      steps_left: @max_simulation_steps
    }

    do_simulate(sim_state)
  end

  @spec do_simulate(simulation()) :: non_neg_integer()
  defp do_simulate(%SimState{steps_left: 0}), do: @unreachable_cost

  defp do_simulate(%SimState{orders: orders, target: target, time_ms: time_ms} = sim_state) do
    if target_cleared?(orders, target),
      do: time_ms,
      else: do_simulate_step(sim_state)
  end

  @spec do_simulate_step(simulation()) :: non_neg_integer()
  defp do_simulate_step(%SimState{orders: orders, elevator_state: elevator_state} = sim_state) do
    {direction, behavior} = Transition.next_action(orders, elevator_state)

    {next_orders, next_elevator_state, delta_ms} =
      case behavior do
        :moving ->
          step = [up: 1, down: -1][direction]
          next_floor = elevator_state.floor + step

          {orders,
           %{
             elevator_state
             | behavior: :moving,
               between_floors: false,
               direction: direction,
               floor: next_floor
           }, @travel_duration_ms}

        :door_open ->
          {clear_orders_at_floor_in_direction(orders, elevator_state.floor, direction),
           %{
             elevator_state
             | behavior: :idle,
               between_floors: false,
               direction: direction
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

  defp clear_orders_at_floor_in_direction(orders, floor, direction) do
    hall_button_to_clear = [up: :hall_up, down: :hall_down][direction]

    Map.update(orders, floor, MapSet.new(), fn floor_orders ->
      floor_orders
      |> MapSet.delete(:cab)
      |> MapSet.delete(hall_button_to_clear)
    end)
  end
end
