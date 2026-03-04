defmodule Elevator.Action do
  @moduledoc """
  Module updating the state based on occuring events.
  """
  require Logger

  alias Elevator.CabOrders
  alias Elevator.HallOrders
  alias Elevator.Decision

  @door_open_time 1000
  @action_interval 200

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

  @spec decide_and_take_action() :: any()
  defp decide_and_take_action() do
    orders = get_my_orders()

    state = Elevator.State.get_state()
    {new_direction, new_behavior} = Decision.next_action(orders, state)
    # Logger.debug( "Deciding on behavior from state:\n #{inspect(state)}\n Orders: #{inspect(orders)}")
    # Logger.debug("Got behavior #{new_direction} and #{new_behavior}")

    cond do
      state.between_floors or state.behavior == :door_open ->
        nil

      new_behavior == :door_open ->
        CabOrders.arrived_at_floor(state.floor)
        HallOrders.arrived_at_floor(state.floor, new_direction)

        Elevator.State.set_direction(new_direction)
        open_door_and_restart_timer()

      new_behavior == :moving ->
        Elevator.State.set_direction(new_direction)
        Elevator.State.set_behavior(new_behavior)

      new_behavior == :idle ->
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
