defmodule Elevator.Hardware.InputPoller do
  @moduledoc """
  Polls buttons, floor sensor and obstruction switch, 
  casts to stateful modules when new data arrives from the driver.
  """

  use GenServer

  alias Elevator.CabOrders
  alias Elevator.HallOrders
  alias Elevator.Hardware.Driver

  @floor_poll_interval_ms 50
  @button_poll_interval_ms 20
  @obstruction_poll_interval_ms 500

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    schedule_button_poll()
    schedule_floor_poll()
    schedule_obstruction_poll()

    {:ok, nil}
  end

  @impl true
  def handle_info(:poll_floor, state) do
    schedule_floor_poll()

    Elevator.FSM.State.set_floor(Driver.get_floor_sensor_state())

    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_obstruction, state) do
    schedule_obstruction_poll()

    obstruction_switch = Driver.get_obstruction_switch_state() == :active
    Elevator.FSM.State.set_obstruction(obstruction_switch)

    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_buttons, state) do
    schedule_button_poll()
    # Polls button and notifies Cab- and HallOrders if any are pressed

    for floor <- 0..(Elevator.num_floors() - 1), button <- get_pressed_buttons_at_floor(floor) do
      case button do
        :cab ->
          CabOrders.button_press(floor)

        hall_button ->
          HallOrders.button_press(floor, hall_button)
      end
    end

    {:noreply, state}
  end

  # Helpers --------------------------------------------------

  defp get_pressed_buttons_at_floor(floor) do
    Elevator.button_types()
    |> Enum.filter(fn button ->
      Driver.get_order_button_state(floor, button) == :active
    end)
  end

  # Schedule functions
  defp schedule_button_poll do
    Process.send_after(self(), :poll_buttons, @button_poll_interval_ms)
  end

  defp schedule_floor_poll do
    Process.send_after(self(), :poll_floor, @floor_poll_interval_ms)
  end

  defp schedule_obstruction_poll do
    Process.send_after(self(), :poll_obstruction, @obstruction_poll_interval_ms)
  end
end
