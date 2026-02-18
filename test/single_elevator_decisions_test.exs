defmodule Elevator.SingleElevatorDecisionsTest do
  use ExUnit.Case, async: true

  alias Elevator.Orders

  test "unknonw floor, :down -> stop,idle" do
    state = %Elevator.State{floor: :unknown, direction: :down, orders: %{}}
    assert Orders.decide_next_direction(state) == {:stop, :idle}
  end

  test "no requests -> stop,idle" do
    state = %Elevator.State{floor: 1, direction: :stop, orders: %{}}
    assert Orders.decide_next_direction(state) == {:stop, :idle}
  end

  test "nearest above -> up,moving" do
    orders = %{3 => MapSet.new([:cab]), 4 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :stop, orders: orders}
    assert Orders.decide_next_direction(state) == {:up, :moving}
  end

  test "nearest below -> down,moving" do
    orders = %{0 => MapSet.new([:cab]), 2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 3, direction: :stop, orders: orders}
    assert Orders.decide_next_direction(state) == {:down, :moving}
  end

  test "cab above -> up,moving" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 1, direction: :down, orders: orders}
    assert Orders.decide_next_direction(state) == {:up, :moving}
  end

  test "same floor -> door_open" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 2, direction: :stop, orders: orders}
    assert Orders.decide_next_direction(state) == {:down, :door_open}
  end

  test "should_stop basic cases" do
    # stop when there's a hall_up at current floor while going up
    orders = %{2 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 2, direction: :up, orders: orders}
    assert Orders.should_stop?(state)

    # don't stop if there are requests above and none at current floor
    orders = %{3 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 1, direction: :up, orders: orders}
    refute Orders.should_stop?(state)

    # stop if no requests above
    orders = %{0 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 2, direction: :up, orders: orders}
    assert Orders.should_stop?(state)
  end

  test "clear orders going up: clears cab and hall_up, keeps hall_down" do
    orders = %{
      2 => MapSet.new([:cab, :hall_up, :hall_down]),
      3 => MapSet.new([:cab])
    }

    state = %Elevator.State{floor: 2, direction: :up, orders: orders}
    new_state = Orders.clear_orders_at_current_floor(state)

    assert new_state.orders == %{
             2 => MapSet.new([:hall_down]),
             3 => MapSet.new([:cab])
           }
  end

  test "clear orders going down: clears cab and hall_down, keeps hall_up" do
    orders = %{
      2 => MapSet.new([:cab, :hall_up, :hall_down]),
      1 => MapSet.new([:cab])
    }

    state = %Elevator.State{floor: 2, direction: :down, orders: orders}
    new_state = Orders.clear_orders_at_current_floor(state)

    assert new_state.orders == %{
             2 => MapSet.new([:hall_up]),
             1 => MapSet.new([:cab])
           }
  end

  test "clear orders when stopped: clears all buttons" do
    orders = %{
      2 => MapSet.new([:cab, :hall_up, :hall_down]),
      3 => MapSet.new([:cab])
    }

    state = %Elevator.State{floor: 2, direction: :stop, orders: orders}
    new_state = Orders.clear_orders_at_current_floor(state)

    refute Map.has_key?(new_state.orders, 2)
    assert new_state.orders == %{3 => MapSet.new([:cab])}
  end
end
