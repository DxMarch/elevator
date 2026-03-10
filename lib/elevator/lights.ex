defmodule Elevator.Lights do
  @moduledoc """
  Watches current order and controls the lights.
  """

  alias Elevator.Decision
  alias Elevator.Driver
  alias Elevator.CabOrders
  alias Elevator.HallOrders
  alias Elevator.Types

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
    set_all_lights()
    Process.sleep(Elevator.light_period())
    loop()
  end

  defp get_light_orders() do
    hall_orders = HallOrders.get_confirmed_orders()
    pressed_cab_floors = CabOrders.get_my_orders()
    Decision.combine_hall_and_cab(hall_orders, pressed_cab_floors)
  end

  defp set_all_lights() do
    orders = get_light_orders()

    for floor <- 0..(Elevator.num_floors() - 1), btn <- Types.btn_types() do
      lights = Map.get(orders, floor, MapSet.new())
      state = if MapSet.member?(lights, btn), do: :on, else: :off
      Driver.set_order_button_light(btn, floor, state)
    end
  end
end
