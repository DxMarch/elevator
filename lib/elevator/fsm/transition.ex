defmodule Elevator.FSM.Transition do
  @moduledoc """
  Loop handling FSM transitions.
  One iteration of the loop does the following:
  - Checks door and motor timeouts
  - Reads and updates state and orders 
  - Sets hardware outputs
  """
  require Logger

  alias Elevator.Types
  alias Elevator.CabOrders
  alias Elevator.FSM.State
  alias Elevator.HallOrders
  alias Elevator.Decision
  alias Elevator.Hardware.Outputs

  @motor_timeout_ms 3500
  @transition_interval_ms 100

  def start_link(_arg) do
    pid = spawn_link(fn -> loop() end)

    {:ok, pid}
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  defp loop() do
    check_door_timer(State.get_state())
    check_motor_timeout(State.get_state())
    decide_and_update_state(State.get_state(), get_my_orders())
    Outputs.set_outputs(State.get_state(), get_light_orders())

    Process.sleep(@transition_interval_ms)
    loop()
  end

  # Helpers ----------------------------------------------------------

  defp get_my_orders() do
    hall_orders = HallOrders.get_my_orders()
    pressed_cab_floors = CabOrders.get_my_orders()
    Decision.combine_hall_and_cab(hall_orders, pressed_cab_floors)
  end

  defp get_light_orders() do
    hall_orders = HallOrders.get_confirmed_orders()
    pressed_cab_floors = CabOrders.get_my_orders()
    Decision.combine_hall_and_cab(hall_orders, pressed_cab_floors)
  end

  @spec decide_and_update_state(Elevator.FSM.State.t(), Types.combined_order_map()) :: any()
  defp decide_and_update_state(state, orders) when not state.motor_timed_out do
    {new_direction, new_behavior} = Decision.next_action(orders, state)

    cond do
      state.behavior == :door_open ->
        CabOrders.arrived_at_floor(state.floor)
        HallOrders.arrived_at_floor(state.floor, new_direction)

      new_behavior == :door_open ->
        State.open_door()
        State.set_direction(new_direction)

      new_behavior == :moving ->
        State.set_direction(new_direction)
        State.set_behavior(new_behavior)

      new_behavior == :idle ->
        State.set_direction(new_direction)
        State.set_behavior(new_behavior)
    end
  end

  defp decide_and_update_state(_state, _orders), do: :ok

  defp check_motor_timeout(state) do
    timed_out =
      case state.last_floor_time do
        nil ->
          false

        last_floor_time ->
          Time.diff(Time.utc_now(), last_floor_time, :millisecond) > @motor_timeout_ms
      end

    State.set_motor_timed_out(timed_out)
  end

  defp check_door_timer(state) do
    if state.behavior == :door_open and
         Time.after?(
           Time.utc_now(),
           Time.add(state.door_open_time_ms, Elevator.door_open_duration_ms(), :millisecond)
         ) do
      if state.obstructed do
        State.open_door()
      else
        State.set_behavior(:idle)
      end
    end
  end
end
