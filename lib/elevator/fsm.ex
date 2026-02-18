defmodule Elevator.FSM do
  @moduledoc """
  Elevator FSM
  """

  use GenServer
  require Logger

  alias Elevator.Driver
  alias Elevator.Types
  alias Elevator.CabOrders
  alias Elevator.HallOrders
  alias Elevator.Orders

  @door_open_time 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    # clear stop and door lights
    Driver.set_stop_button_light(:off)
    Driver.set_door_open_light(:off)

    floor = Driver.get_floor_sensor_state()

    state = %Elevator.State{}

    state =
      if floor == :between_floors do
        Driver.set_motor_direction(:down)
        Logger.debug("Initialized between floors, going down")
        %{state | behavior: :moving}
      else
        %{state | floor: floor}
      end

    {:ok, state}
  end

  # User API ---------------------------------------------------------

  def sensed_new_floor(floor) do
    GenServer.cast(__MODULE__, {:sensed_new_floor, floor})
  end

  @spec order_button_pressed(Types.floor(), Types.btn_type()) :: :ok
  def order_button_pressed(floor, dir) do
    GenServer.cast(__MODULE__, {:order_button_pressed, floor, dir})
  end

  # calls ------------------------------------------------------------

  @impl true
  def handle_info({:close_door, close_ref}, %{door_timer: {_timer_ref, close_ref}} = state) do
    if Driver.get_obstruction_switch_state() == :active do
      new_state = open_door_and_restart_timer(state)
      {:noreply, new_state}
    else
      Driver.set_door_open_light(:off)
      new_state = %{state | behavior: :idle, door_timer: nil}

      new_state = decide_and_take_action(new_state)

      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:close_door, _stale_ref}, state) do
    {:noreply, state}
  end

  # Casts ------------------------------------------------------------

  @impl true
  def handle_cast({:sensed_new_floor, floor}, state) do
    Logger.debug("Sensed new floor #{floor}, current state: #{inspect(state)}")
    Driver.set_floor_indicator(floor)
    new_state = %{state | floor: floor}

    new_state =
      if Orders.should_stop?(get_all_orders(), new_state) do
        Driver.set_motor_direction(:stop)

        CabOrders.arrived_at_floor(floor)
        HallOrders.arrived_at_floor(floor, new_state.direction)
        # TODO: Init shouldn't open door
        open_door_and_restart_timer(new_state)
      else
        new_state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:order_button_pressed, floor, btn}, state) do
    case state.behavior do
      :door_open ->
        if Orders.should_clear_immediately?(state, floor, btn) do
          {:noreply, open_door_and_restart_timer(state)}
        else
          handle_button_press(floor, btn)
          {:noreply, state}
        end

      :moving ->
        handle_button_press(floor, btn)
        {:noreply, state}

      :idle ->
        handle_button_press(floor, btn)
        {:noreply, decide_and_take_action(state)}
    end
  end

  # Helpers ----------------------------------------------------------

  @spec handle_button_press(Types.floor(), Types.btn_type()) :: any()
  defp handle_button_press(floor, btn) do
    if btn == :cab do
      CabOrders.button_pressed(floor)
    else
      HallOrders.button_press(floor, btn)
    end
  end

  defp get_all_orders() do
    hall_orders = HallOrders.get_my_orders()
    pressed_cab_floors = CabOrders.get_my_orders()
    Orders.combine_hall_and_cab(hall_orders, pressed_cab_floors)
  end

  defp decide_and_take_action(state) do
    orders = get_all_orders()
    set_all_lights(orders)

    Logger.debug(
      "Deciding on behavior from state:\n #{inspect(state)}\n Orders: #{inspect(orders)}"
    )

    {direction, new_behavior} = Orders.decide_next_direction(orders, state)
    Logger.debug("Got behavior #{direction} and #{new_behavior}")

    case new_behavior do
      :door_open ->
        CabOrders.arrived_at_floor(state.floor)
        HallOrders.arrived_at_floor(state.floor, direction)
        new_state = open_door_and_restart_timer(state)
        %{new_state | direction: direction, behavior: new_behavior}

      :moving ->
        cancel_door_timer(state.door_timer)
        Driver.set_motor_direction(direction)
        %{state | direction: direction, behavior: new_behavior, door_timer: nil}

      :idle ->
        cancel_door_timer(state.door_timer)
        Driver.set_motor_direction(:stop)
        %{state | direction: direction, behavior: new_behavior, door_timer: nil}
    end
  end

  defp set_all_lights(orders) do
    # TODO: Currently this will only set lights if the orders are for the current elevator.
    # In practice we probably want to also set hall lights if others have accepted a order on the floor
    # This could probably be done by seperating into set_hall_lights and set_cab_lights and call them from their respective cast
    for floor <- 0..(Elevator.num_floors() - 1), btn <- Types.btn_types() do
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

    %{state | behavior: :door_open, direction: :stop, door_timer: {timer_ref, close_ref}}
  end

  defp cancel_door_timer(nil), do: :ok
  defp cancel_door_timer({timer_ref, _close_ref}), do: Process.cancel_timer(timer_ref)
end
