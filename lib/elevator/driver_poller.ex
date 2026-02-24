defmodule Elevator.DriverPoller do
  @moduledoc """
  Polls buttons, floor sensor and obstruction switch, casts to FSM when new info
  """

  use GenServer
  require Logger

  alias Elevator.Driver
  alias Elevator.FSM

  @floor_poll_interval 50
  @button_poll_interval 150
  # @obstruction_poll_interval 200

  @buttons [:hall_up, :hall_down, :cab]

  # Public API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # GenServer callbacks
  @impl true
  def init(_state) do
    schedule_button_poll()
    schedule_floor_poll()
    # schedule_obstruction_poll()

    {:ok, %{prev_floor: :unknown, prev_buttons: MapSet.new(), obstructed: :unknown}}
  end

  @impl true
  def handle_info(:poll_floor, state) do
    # Polls floor and notifies FSM if we arrive at a new floor

    prev_floor = Map.fetch!(state, :prev_floor)
    floor = Driver.get_floor_sensor_state()

    schedule_floor_poll()

    cond do
      floor == :between_floors ->
        {:noreply, state}

      floor != prev_floor ->
        FSM.sensed_new_floor(floor)
        {:noreply, %{state | prev_floor: floor}}

      true ->
        {:noreply, state}
    end
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

  # @impl true
  # def handle_info(:poll_obstruction, state) do
  #   # Polls obstruction switch and notifies FSM if its on
  #   # Doesn't really need to be polled when door isn't open,
  #   # but doesn't really hurt either
  #   prev_obstruction_state = Map.fetch!(state, :obstructed)
  #   obstruction_state = Driver.get_obstruction_switch_state()

  #   case obstruction_state do
  #     ^prev_obstruction_state -> :ok
  #     :active -> FSM.door_obstructed()
  #     :inactive -> FSM.door_cleared()
  #   end

  #   schedule_obstruction_poll()
  #   {:noreply, %{state | obstructed: obstruction_state}}
  # end

  # Helpers

  defp get_pressed_buttons_at_floor(floor) do
    @buttons
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

  # defp schedule_obstruction_poll do
  #   Process.send_after(self(), :poll_obstruction, @obstruction_poll_interval)
  # end
end
