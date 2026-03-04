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
  @action_interval 50

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_state) do
    # clear stop and door lights
    Driver.set_motor_direction(:stop)

    floor = Driver.get_floor_sensor_state()
    if floor == :between_floors do
      Elevator.State.set_behavior(:moving)
      Elevator.State.set_direction(:down)
      Driver.set_motor_direction(:down)
    end

    Process.send(self(), :poll_action, [])

    {:ok, []}
  end

  # User API ---------------------------------------------------------
  @spec order_button_pressed(Types.floor(), Types.btn_type()) :: :ok
  def order_button_pressed(floor, dir) do
    GenServer.cast(__MODULE__, {:order_button_pressed, floor, dir})
  end

  # Info messages -----------------------------------------------------

  @impl true
  def handle_info(:poll_action, state) do
    Process.send_after(self(), :poll_action, @action_interval)
    poll_door_timer()
    decide_and_take_action()
    {:noreply, state}
  end

  # Casts ------------------------------------------------------------

  @impl true
  def handle_cast({:order_button_pressed, floor, btn}, _state) do
    state = Elevator.State.get_state()

    case state.behavior do
      :door_open ->
        if Decision.should_clear_immediately?(state, floor, btn) do
          open_door_and_restart_timer()
        else
          notify_button_press(floor, btn)
        end
      _ ->
        notify_button_press(floor, btn)
    end
    {:noreply, []}
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

  @spec decide_and_take_action() :: any()
  defp decide_and_take_action() do
    orders = get_my_orders()

    state = Elevator.State.get_state()
    {new_direction, new_behavior} = Decision.next_action(orders, state)
    # Logger.debug( "Deciding on behavior from state:\n #{inspect(state)}\n Orders: #{inspect(orders)}")
    # Logger.debug("Got behavior #{new_direction} and #{new_behavior}")

    cond do
      state.between_floors ->
        state
      state.behavior == :door_open ->
        state

      new_behavior == :door_open ->
        Driver.set_motor_direction(:stop)

        CabOrders.arrived_at_floor(state.floor)
        HallOrders.arrived_at_floor(state.floor, new_direction)

        Elevator.State.set_direction(new_direction)
        open_door_and_restart_timer()

      new_behavior == :moving ->
        Driver.set_motor_direction(new_direction)
        Elevator.State.set_direction(new_direction)
        Elevator.State.set_behavior(new_behavior)

      new_behavior == :idle ->
        Driver.set_motor_direction(:stop)
        Elevator.State.set_direction(new_direction)
        Elevator.State.set_behavior(new_behavior)
    end
  end

  defp poll_door_timer() do
    state = Elevator.State.get_state()
    if state.behavior == :door_open and Time.after?(Time.utc_now(), Time.add(state.door_open_time, @door_open_time, :millisecond)) do
      Elevator.State.set_behavior(:idle)
    end
  end

  defp open_door_and_restart_timer() do
    Elevator.State.set_behavior(:door_open)
    Elevator.State.set_door_open_time(Time.utc_now())
  end
end
