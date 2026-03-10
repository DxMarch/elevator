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
  alias Elevator.Decision

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
        %{state | direction: :down, behavior: :moving}
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

  def hall_orders_updated() do
    GenServer.cast(__MODULE__, :hall_orders_updated)
  end

  # Info messages -----------------------------------------------------

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

    new_state = decide_and_take_action(%{new_state | behavior: :idle})

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:order_button_pressed, floor, btn}, state) do
    new_state =
      case state.behavior do
        :door_open ->
          if Decision.should_clear_immediately?(state, floor, btn) do
            open_door_and_restart_timer(state)
          else
            notify_button_press(floor, btn)
            state
          end

        :moving ->
          notify_button_press(floor, btn)
          state

        :idle ->
          notify_button_press(floor, btn)
          decide_and_take_action(state)
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:hall_orders_updated, state) do
    new_state =
      if state.behavior == :idle do
        decide_and_take_action(state)
      else
        state
      end

    {:noreply, new_state}
  end

  # Helpers ----------------------------------------------------------

  @spec notify_button_press(Types.floor(), Types.btn_type()) :: any()
  defp notify_button_press(floor, btn) do
    if btn == :cab do
      CabOrders.button_press(floor)
    else
      HallOrders.button_press(floor, btn)
    end
  end

  defp get_my_orders() do
    hall_orders = HallOrders.get_my_orders()
    pressed_cab_floors = CabOrders.get_my_orders()
    Decision.combine_hall_and_cab(hall_orders, pressed_cab_floors)
  end

  @spec decide_and_take_action(Elevator.State.t()) :: Elevator.State.t()
  defp decide_and_take_action(state) do
    orders = get_my_orders()

    Logger.debug(
      "Deciding on behavior from state:\n #{inspect(state)}\n Orders: #{inspect(orders)}"
    )

    {new_direction, new_behavior} = Decision.next_action(orders, state)
    Logger.debug("Got behavior #{new_direction} and #{new_behavior}")

    case new_behavior do
      :door_open ->
        CabOrders.arrived_at_floor(state.floor)
        HallOrders.arrived_at_floor(state.floor, new_direction)
        open_door_and_restart_timer(%{state | direction: new_direction})

      :moving ->
        cancel_door_timer(state.door_timer)
        Driver.set_motor_direction(new_direction)
        %{state | direction: new_direction, behavior: new_behavior, door_timer: nil}

      :idle ->
        cancel_door_timer(state.door_timer)
        Driver.set_motor_direction(:stop)
        %{state | direction: new_direction, behavior: new_behavior, door_timer: nil}
    end
  end

  defp open_door_and_restart_timer(state) do
    cancel_door_timer(state.door_timer)
    Driver.set_motor_direction(:stop)
    Driver.set_door_open_light(:on)

    close_ref = make_ref()
    timer_ref = Process.send_after(self(), {:close_door, close_ref}, @door_open_time)

    %{state | behavior: :door_open, door_timer: {timer_ref, close_ref}}
  end

  defp cancel_door_timer(nil), do: :ok
  defp cancel_door_timer({timer_ref, _close_ref}), do: Process.cancel_timer(timer_ref)
end
