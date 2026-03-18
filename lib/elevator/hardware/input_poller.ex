defmodule Elevator.Hardware.InputPoller do
  @moduledoc """
  Polls buttons, floor sensor and external order updates, casts to stateful modules when new info
  """

  use GenServer
  require Logger

  alias Elevator.CabOrders
  alias Elevator.HallOrders
  alias Elevator.Hardware.Driver

  @floor_poll_interval_ms 50
  @button_poll_interval_ms 20
  @obstruction_poll_interval_ms 500

  # Public API
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # GenServer callbacks
  @impl true
  def init(_state) do
    schedule_button_poll()
    schedule_floor_poll()
    schedule_obstruction_poll()

    {:ok, %{prev_buttons: MapSet.new()}}
  end

  @impl true
  def handle_info(:poll_floor, state) do
    schedule_floor_poll()

    floor = Driver.get_floor_sensor_state()
    Elevator.FSM.State.set_floor(floor)

    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_obstruction, state) do
    schedule_obstruction_poll()

    switch_state = Driver.get_obstruction_switch_state()
    obstructed = switch_state == :active
    Elevator.FSM.State.set_obstruction(obstructed)

    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_buttons, state) do
    schedule_button_poll()
    # Polls button and notifies Cab- and HallOrders if any are pressed

    current_buttons =
      for floor <- 0..(Elevator.num_floors() - 1),
          btn <- get_pressed_buttons_at_floor(floor),
          into: MapSet.new() do
        {floor, btn}
      end

    # Only notify on new presses (in current but not in previous)
    new_presses = MapSet.difference(current_buttons, state.prev_buttons)

    Enum.each(new_presses, fn {floor, btn} ->
      case btn do
        :cab ->
          CabOrders.button_press(floor)

        hall_btn ->
          HallOrders.button_press(floor, hall_btn)
      end
    end)

    {:noreply, %{state | prev_buttons: current_buttons}}
  end

  # Helpers

  defp get_pressed_buttons_at_floor(floor) do
    Elevator.Types.btn_types()
    |> Enum.filter(fn btn ->
      Driver.get_order_button_state(floor, btn) == :active
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
