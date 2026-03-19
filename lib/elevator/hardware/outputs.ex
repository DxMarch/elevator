defmodule Elevator.Hardware.Outputs do
  @moduledoc """
  Sets driver outputs given state and orders. 
  """

  require Logger
  alias Elevator.Hardware.Driver
  alias Elevator.FSM

  @spec init() :: :ok
  def init() do
    Driver.set_stop_button_light(:off)
    Driver.set_door_open_light(:off)
    Driver.set_motor_direction(:stop)
  end

  @spec set_outputs(FSM.State.t(), Elevator.OrderUtils.combined_order_map()) :: :ok
  def set_outputs(state, light_orders) do
    set_door_light(state)
    set_motors(state)
    set_floor_light(state)
    set_order_lights(light_orders)
    :ok
  end

  defp set_motors(elevator_state) do
    case elevator_state.behavior do
      :moving ->
        Driver.set_motor_direction(elevator_state.direction)

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
    for floor <- 0..(Elevator.num_floors() - 1), button <- Elevator.button_types() do
      orders_at_floor = Map.get(orders, floor, MapSet.new())
      state = if MapSet.member?(orders_at_floor, button), do: :on, else: :off
      Driver.set_order_button_light(button, floor, state)
    end
  end

  defp set_door_light(%{behavior: behavior} = _elevator_state) do
    case behavior do
      :door_open ->
        Driver.set_door_open_light(:on)

      _ ->
        Driver.set_door_open_light(:off)
    end
  end
end
