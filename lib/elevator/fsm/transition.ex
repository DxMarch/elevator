defmodule Elevator.FSM.Transition do
  @moduledoc """
  Loop handling FSM transitions.
  One iteration of the loop does the following:
  - Checks door and motor timeouts
  - Reads and updates state and orders 
  - Sets hardware outputs
  """
  require Logger

  alias Elevator.CabOrders
  alias Elevator.FSM.State
  alias Elevator.HallOrders
  alias Elevator.Hardware.Outputs
  alias Elevator.OrderUtils

  @motor_timeout_ms 3500
  @transition_interval_ms 100

  @spec start_link(any()) :: {:ok, pid()}
  def start_link(_arg) do
    pid = spawn_link(fn -> loop() end)

    {:ok, pid}
  end

  @spec child_spec(any()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @doc """
  Computes the elevator's next `{direction, behavior}` pair 
  from current orders and elevator state.

  Tries to keep moving in the same direction.
  """
  @spec next_action(Elevator.OrderUtils.combined_order_map(), Elevator.FSM.State.t()) ::
          {:up | :down, :moving | :door_open | :idle}
  def next_action(
        orders,
        %Elevator.FSM.State{
          direction: direction,
          floor: floor,
          between_floors: between_floors
        }
      ) do
    buttons_at_floor = Map.get(orders, floor, MapSet.new())

    cond do
      between_floors ->
        {direction, :moving}

      map_size(orders) == 0 ->
        {direction, :idle}

      direction == :up ->
        cond do
          MapSet.member?(buttons_at_floor, :hall_up) or MapSet.member?(buttons_at_floor, :cab) ->
            {:up, :door_open}

          OrderUtils.orders_above?(orders, floor) ->
            {:up, :moving}

          MapSet.member?(buttons_at_floor, :hall_down) ->
            {:down, :door_open}

          OrderUtils.orders_below?(orders, floor) ->
            {:down, :moving}

          true ->
            {:up, :idle}
        end

      direction == :down ->
        cond do
          MapSet.member?(buttons_at_floor, :hall_down) or MapSet.member?(buttons_at_floor, :cab) ->
            {:down, :door_open}

          OrderUtils.orders_below?(orders, floor) ->
            {:down, :moving}

          MapSet.member?(buttons_at_floor, :hall_up) ->
            {:up, :door_open}

          OrderUtils.orders_above?(orders, floor) ->
            {:up, :moving}

          true ->
            {:down, :idle}
        end
    end
  end

  defp loop() do
    check_door_timer(State.get_state())
    check_motor_timeout(State.get_state())
    decide_and_update_state(State.get_state(), get_my_orders())
    Outputs.set_outputs(State.get_state(), get_light_orders())

    Process.sleep(@transition_interval_ms)
    loop()
  end

  # Helpers --------------------------------------------------

  defp get_my_orders() do
    hall_orders = HallOrders.get_my_orders()
    cab_orders = CabOrders.get_my_orders()
    OrderUtils.combine_hall_and_cab(hall_orders, cab_orders)
  end

  defp get_light_orders() do
    hall_orders = HallOrders.get_handling_orders()
    cab_orders = CabOrders.get_my_orders()
    OrderUtils.combine_hall_and_cab(hall_orders, cab_orders)
  end

  @spec decide_and_update_state(Elevator.FSM.State.t(), Elevator.OrderUtils.combined_order_map()) ::
          any()
  defp decide_and_update_state(state, orders) when not state.motor_timed_out do
    {new_direction, new_behavior} = next_action(orders, state)

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

  defp decide_and_update_state(_state, _orders), do: :ok

  defp check_motor_timeout(state) do
    timed_out =
      state.behavior == :moving and
        Time.diff(Time.utc_now(), state.last_floor_time, :millisecond) > @motor_timeout_ms

    State.set_motor_timed_out(timed_out)
  end

  defp check_door_timer(state) when state.behavior == :door_open do
    timed_out =
      Time.diff(Time.utc_now(), state.door_open_time, :millisecond) >
        Elevator.door_open_duration_ms()

    cond do
      timed_out and state.obstructed ->
        State.open_door()

      timed_out ->
        State.set_behavior(:idle)

      true ->
        :ok
    end
  end

  defp check_door_timer(_), do: :ok
end
