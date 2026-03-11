defmodule Elevator.Hardware.OutputPoller do
  @moduledoc """
  Watches current state and controls the physical elevator. 
  """

  require Logger
  alias Elevator.CabOrders
  alias Elevator.Decision
  alias Elevator.HallOrders
  alias Elevator.Hardware.Driver
  alias Elevator.Types

  @output_poll_interval 50

  def start_link(_arg) do
    Driver.set_stop_button_light(:off)
    Driver.set_door_open_light(:off)
    Driver.set_motor_direction(:stop)

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
    state = Elevator.FSM.State.get_state()
    orders = get_light_orders()
    set_order_lights(orders)
    set_door_light(state)
    set_motors(state)
    Process.sleep(@output_poll_interval)
    loop()
  end

  defp set_motors(elev_state) do
    case elev_state.behavior do
      :moving ->
        Driver.set_motor_direction(elev_state.direction)

      _ ->
        Driver.set_motor_direction(:stop)
    end
  end

  defp get_light_orders() do
    hall_orders = HallOrders.get_confirmed_orders()
    pressed_cab_floors = CabOrders.get_my_orders()
    Decision.combine_hall_and_cab(hall_orders, pressed_cab_floors)
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
