defmodule Elevator.Poller do
  @moduledoc """
  Polls buttons, floor sensor and external order updates, casts to FSM when new info
  """

  use GenServer
  require Logger

  alias Elevator.Driver
  alias Elevator.FSM

  @floor_poll_interval 50
  @button_poll_interval 20

  # Public API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # GenServer callbacks
  @impl true
  def init(_state) do
    schedule_button_poll()
    schedule_floor_poll()

    {:ok,
     %{
       prev_floor: :unknown,
       prev_buttons: MapSet.new(),
       hall_orders: %{},
       obstructed: :unknown
     }}
  end

  @impl true
  def handle_info(:poll_floor, state) do
    # Polls floor and notifies FSM if we arrive at a new floor
    schedule_floor_poll()


    floor = Driver.get_floor_sensor_state()
    Elevator.State.set_floor(floor)

    {:noreply, state}
  end

  @impl true
  def handle_info(:poll_buttons, state) do
    # Polls button and notifies FSM if any are pressed

    prev_buttons = Map.get(state, :prev_buttons, MapSet.new())

    current_buttons =
      for floor <- 0..(Elevator.num_floors() - 1),
          btn <- get_pressed_buttons_at_floor(floor),
          into: MapSet.new() do
        {floor, btn}
      end

    # Only notify on new presses (in current but not in previous)
    new_presses = MapSet.difference(current_buttons, prev_buttons)

    Enum.each(new_presses, fn {floor, btn} ->
      FSM.order_button_pressed(floor, btn)
    end)

    schedule_button_poll()
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
    Process.send_after(self(), :poll_buttons, @button_poll_interval)
  end

  defp schedule_floor_poll do
    Process.send_after(self(), :poll_floor, @floor_poll_interval)
  end
end
