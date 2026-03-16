defmodule Test.Single.CostTest do
  use ExUnit.Case, async: false

  alias Elevator.CabOrders
  alias Elevator.FSM.State
  alias Elevator.HallOrders.Cost

  @travel_duration_ms 2500
  @unreachable_cost 30000
  @state_settle_ms 10

  setup do
    start_supervised!({CabOrders, []})
    start_supervised!({Elevator.HallOrders, Elevator.num_floors()})
    start_supervised!(State)

    :ok
  end

  test "same-floor request in current direction costs one door cycle" do
    set_state(floor: 1, direction: :up, behavior: :idle)

    assert Cost.compute_cost({1, :hall_up}, %{}) == Elevator.door_open_duration_ms()
  end

  test "same-floor opposite request is served immediately when no further requests" do
    set_state(floor: 1, direction: :up, behavior: :idle)

    assert Cost.compute_cost({1, :hall_down}, %{}) == Elevator.door_open_duration_ms()
  end

  test "one floor away request costs travel plus door time" do
    set_state(floor: 0, direction: :up, behavior: :idle)

    assert Cost.compute_cost({1, :hall_up}, %{}) ==
             @travel_duration_ms + Elevator.door_open_duration_ms()
  end

  test "unknown floor yields unreachable cost" do
    set_state(floor: :unknown, direction: :down, behavior: :idle)

    assert Cost.compute_cost({1, :hall_up}, %{}) == @unreachable_cost
  end

  defp set_state(opts) do
    State.set_direction(Keyword.fetch!(opts, :direction))
    State.set_behavior(Keyword.fetch!(opts, :behavior))
    State.set_floor(Keyword.fetch!(opts, :floor))
    # Wait for GenServer casts to settle
    Process.sleep(@state_settle_ms)
  end
end
