defmodule Elevator.FSM.Action do
  @moduledoc """
  Module updating the state based on occuring events.
  """
  require Logger

  alias Elevator.CabOrders
  alias Elevator.FSM.State
  alias Elevator.HallOrders
  alias Elevator.Decision

  @door_open_time 1000
  @motor_timeout 4000
  @action_interval 100

  def start_link(_arg) do
    pid = spawn_link(fn -> poll_action() end)

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

  defp poll_action() do
    poll_door_timer()
    check_motor_timeout()
    decide_and_take_action()
    Process.sleep(@action_interval)
    poll_action()
  end

  # Helpers ----------------------------------------------------------

  defp get_my_orders() do
    hall_orders = HallOrders.get_my_orders()
    pressed_cab_floors = CabOrders.get_my_orders()
    Decision.combine_hall_and_cab(hall_orders, pressed_cab_floors)
  end

  defp check_motor_timeout() do
    state = State.get_state()

    timed_out =
      case state.last_floor_time do
        nil ->
          false

        last_floor_time ->
          Time.diff(Time.utc_now(), last_floor_time, :millisecond) > @motor_timeout
      end

    State.set_motor_timed_out(timed_out)
  end

  @spec decide_and_take_action() :: any()
  defp decide_and_take_action() do
    state = State.get_state()

    if state.motor_timed_out do
      :ok
    else
      orders = get_my_orders()

      {new_direction, new_behavior} = Decision.next_action(orders, state)

      # Logger.debug("Deciding on behavior from state:\n #{inspect(state)}\n Orders: #{inspect(orders)}")
      # Logger.debug("Got behavior #{new_direction} and #{new_behavior}")

      cond do
        state.behavior == :door_open ->
          CabOrders.arrived_at_floor(state.floor)
          HallOrders.arrived_at_floor(state.floor, new_direction)

        new_behavior == :door_open ->
          State.open_door()
          State.set_direction(new_direction)

        new_behavior == :moving ->
          State.set_direction(new_direction)
          State.set_behavior(new_behavior)

        new_behavior == :idle ->
          State.set_direction(new_direction)
          State.set_behavior(new_behavior)
      end
    end
  end

  defp poll_door_timer() do
    state = State.get_state()

    if state.behavior == :door_open and
         Time.after?(
           Time.utc_now(),
           Time.add(state.door_open_time, @door_open_time, :millisecond)
         ) do
      if state.obstructed do
        State.open_door()
      else
        State.set_behavior(:idle)
      end
    end
  end
end
