defmodule Elevator.Hardware.Outputs do
  @moduledoc """
  Watches current state and controls the physical elevator.
  """

  require Logger
  alias Elevator.Communicator
  alias Elevator.Hardware.Driver
  alias Elevator.Types
  alias Elevator.FSM

  def init() do
    Driver.set_stop_button_light(:off)
    Driver.set_door_open_light(:off)
    Driver.set_motor_direction(:stop)
  end

  @spec set_outputs(FSM.State.t(), Types.combined_order_map()) :: any()
  def set_outputs(state, light_orders) do
    set_door_light(state)
    set_motors(state)
    set_floor_light(state)

    door_blocked = state.behavior == :door_open and state.obstructed
    operational = not (door_blocked or state.motor_timed_out)
    Communicator.update_operation_status(operational)

    set_order_lights(light_orders)
  end

  defp set_motors(elev_state) do
    case elev_state.behavior do
      :moving ->
        Driver.set_motor_direction(elev_state.direction)

      _ ->
        Driver.set_motor_direction(:stop)
    end
  end

  defp set_floor_light(state) do
    if state.floor != :unknown do
      Driver.set_floor_indicator(state.floor)
    end
  end

  defp set_order_lights(orders) do
    for floor <- 0..(Elevator.num_floors() - 1), btn <- Types.btn_types() do
      lights = Map.get(orders, floor, MapSet.new())
      state = if MapSet.member?(lights, btn), do: :on, else: :off
      Driver.set_order_button_light(btn, floor, state)
    end
  end

  defp set_door_light(elev_state) do
    behavior = elev_state.behavior

    case behavior do
      :door_open ->
        Driver.set_door_open_light(:on)

      _ ->
        Driver.set_door_open_light(:off)
    end
  end
end
