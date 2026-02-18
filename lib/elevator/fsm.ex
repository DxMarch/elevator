defmodule Elevator.FSM do
  @moduledoc """
  Elevator FSM
  """

  # TODO: I think it's a bad idea to keep a copy of orders in the elevator state strcut. It would be way more explicit that hall_orders and cab_orders are the single source of truth.
  # I could possibly create a helper taking in the types defined for hall_order_map and cab_order_map that spits out combined_order_map that can be used by orders.ex

  use GenServer
  require Logger

  alias Elevator.Driver
  alias Elevator.Types
  alias Elevator.CabOrders
  alias Elevator.Orders

  @door_open_time 1000

  @buttons [:hall_up, :hall_down, :cab]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # GenServer callbacks
  @impl true
  def init(_state) do
    # clear stop and door lights
    Driver.set_stop_button_light(:off)
    Driver.set_door_open_light(:off)

    floor = Driver.get_floor_sensor_state()

    state = %Elevator.State{}

    state =
      cond do
        floor == :between_floors ->
          Driver.set_motor_direction(:down)
          Logger.debug("Going down")

          Map.put(state, :direction, :down)
          |> Map.put(:behavior, :moving)

        is_integer(floor) ->
          Map.put(state, :floor, floor)
      end

    {:ok, state}
  end

  # User API ---------------------------------------------------------

  def sensed_new_floor(floor) do
    GenServer.cast(__MODULE__, {:sensed_new_floor, floor})
  end

  @spec cab_button_pressed(Types.floor()) :: :ok
  def cab_button_pressed(floor) do
    GenServer.cast(__MODULE__, {:cab_button_pressed, floor})
  end

  @spec hall_button_pressed(Types.floor(), Types.hall_btn()) :: :ok
  def hall_button_pressed(floor, dir) do
    GenServer.cast(__MODULE__, {:hall_button_pressed, floor, dir})
  end

  def door_obstructed() do
    # TODO: A bit unsure how this really should be handled, it doesn't really make sense
    # that the door can be obstructed when it's closed,
    # but the spec says it can be triggered/un-triggered "anytime"
    Logger.debug("Door obstructed")
  end

  def door_cleared() do
    Logger.debug("Door cleared")
  end

  # calls ------------------------------------------------------------

  @impl true
  def handle_info({:close_door, close_ref}, %{door_timer: {_timer_ref, close_ref}} = state) do
    # TODO: Check obstruction here?
    Driver.set_door_open_light(:off)
    new_state = %{state | behavior: :idle, door_timer: nil}
    {:noreply, new_state, {:continue, :do_behavior}}
  end

  @impl true
  def handle_info({:close_door, _stale_ref}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_continue(:do_behavior, state) do
    IO.puts("Deciding on behavior from state: ")
    IO.inspect(state)

    {direction, behavior} = Orders.decide_next_direction(state)
    IO.puts("Got behavior #{direction} and #{behavior}")

    case behavior do
      :door_open ->
        state = open_door_and_restart_timer(state)
        {:noreply, %{state | direction: direction, behavior: behavior}}

      :moving ->
        cancel_door_timer(state.door_timer)
        Driver.set_motor_direction(direction)
        {:noreply, %{state | direction: direction, behavior: behavior, door_timer: nil}}

      :idle ->
        cancel_door_timer(state.door_timer)
        Driver.set_motor_direction(:stop)
        {:noreply, %{state | direction: direction, behavior: behavior, door_timer: nil}}
    end
  end

  # Casts ------------------------------------------------------------

  @impl true
  def handle_cast({:sensed_new_floor, floor}, state) do
    IO.puts("Sensed new floor #{floor}, current state:")
    IO.inspect(state)
    new_state = %{state | floor: floor}

    new_state =
      if Orders.should_stop?(new_state) do
        Logger.debug("Should stop")
        Driver.set_motor_direction(:stop)
        cleared = Orders.clear_orders_at_current_floor(new_state)

        %{cleared | behavior: :door_open}
        |> open_door_and_restart_timer()
      else
        new_state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:cab_button_pressed, floor}, state) do
    if floor == state.floor and state.behavior != :moving do
      new_state =
        %{state | behavior: :door_open, direction: :stop}
        |> open_door_and_restart_timer()

      {:noreply, new_state}
    else
      new_orders = Orders.combine_new_cab_orders(state.orders, CabOrders.add(floor))
      new_state = %{state | orders: new_orders}
      {:noreply, new_state, {:continue, :do_behavior}}
    end
  end

  @impl true
  def handle_cast({:hall_button_pressed, floor, dir}, state) do
    Logger.debug("Hall button pressed on floor #{floor} direction #{dir}")

    # Send message to hall module -> responds with all hall orders
    # (Maybe?) ask for cab orders -> respond with cab orders
    # Combine into orders
    # Ask order module for behavior -> do behavior
    {:noreply, state}
  end

  # Hardware interface ------------------------------------------------

  defp set_all_lights(orders) do
    # TODO: Currently this will only set lights if the orders are for the current elevator.
    # In practice we probably want to also set hall lights if others have accepted a order on the floor
    # This could probably be done by seperating into set_hall_lights and set_cab_lights and call them from their respective cast
    for floor <- 0..(Elevator.num_floors - 1), btn <- @buttons do
      lights = Map.get(orders, floor, MapSet.new())
      state = if MapSet.member?(lights, btn), do: :on, else: :off
      Driver.set_order_button_light(btn, floor, state)
    end
  end

  defp open_door_and_restart_timer(state) do
    cancel_door_timer(state.door_timer)
    Driver.set_door_open_light(:on)
    close_ref = make_ref()
    timer_ref = Process.send_after(self(), {:close_door, close_ref}, @door_open_time)
    %{state | door_timer: {timer_ref, close_ref}}
  end

  defp cancel_door_timer(nil), do: :ok
  defp cancel_door_timer({timer_ref, _close_ref}), do: Process.cancel_timer(timer_ref)
end
