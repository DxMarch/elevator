defmodule Test.Single.DecisionsTest do
  use ExUnit.Case, async: true

  alias Elevator.Orders

  test "unknonw floor, :down -> stop,idle" do
    orders = %{}
    state = %Elevator.State{floor: :unknown, direction: :down}
    assert Orders.decide_next_direction(orders, state) == {:stop, :idle}
  end

  test "no requests -> stop,idle" do
    orders = %{}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Orders.decide_next_direction(orders, state) == {:stop, :idle}
  end

  test "nearest above -> up,moving" do
    orders = %{3 => MapSet.new([:cab]), 4 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Orders.decide_next_direction(orders, state) == {:up, :moving}
  end

  test "nearest below -> down,moving" do
    orders = %{0 => MapSet.new([:cab]), 2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 3, direction: :stop}
    assert Orders.decide_next_direction(orders, state) == {:down, :moving}
  end

  test "cab above -> up,moving" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 1, direction: :down}
    assert Orders.decide_next_direction(orders, state) == {:up, :moving}
  end

  test "same floor cab -> stop,door_open" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 2, direction: :stop}
    assert Orders.decide_next_direction(orders, state) == {:stop, :door_open}
  end

  test "same floor hall_up -> up,door_open" do
    orders = %{1 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Orders.decide_next_direction(orders, state) == {:up, :door_open}
  end

  test "same floor hall_down -> down,door_open" do
    orders = %{1 => MapSet.new([:hall_down])}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Orders.decide_next_direction(orders, state) == {:down, :door_open}
  end

  test "same floor hall_up while moving up -> up,door_open" do
    orders = %{1 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :up}
    assert Orders.decide_next_direction(orders, state) == {:up, :door_open}
  end

  test "same floor hall_down while moving down -> down,door_open" do
    orders = %{1 => MapSet.new([:hall_down])}
    state = %Elevator.State{floor: 1, direction: :down}
    assert Orders.decide_next_direction(orders, state) == {:down, :door_open}
  end

  test "should_stop basic cases" do
    # stop when there's a hall_up at current floor while going up
    orders = %{2 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 2, direction: :up}
    assert Orders.should_stop?(orders, state)

    # don't stop if there are requests above and none at current floor
    orders = %{3 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 1, direction: :up}
    refute Orders.should_stop?(orders, state)

    # stop if no requests above
    orders = %{0 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 2, direction: :up}
    assert Orders.should_stop?(orders, state)
  end

  test "should_clear_immediately?" do
    door_open_up = %Elevator.State{floor: 2, direction: :up, behavior: :door_open}

    assert Orders.should_clear_immediately?(door_open_up, 2, :cab)
    assert Orders.should_clear_immediately?(door_open_up, 2, :hall_up)

    refute Orders.should_clear_immediately?(door_open_up, 2, :hall_down)
    refute Orders.should_clear_immediately?(door_open_up, 3, :cab)

    moving = %Elevator.State{floor: 2, direction: :up, behavior: :moving}
    assert Orders.should_clear_immediately?(moving, 2, :cab)

    door_open_stop = %Elevator.State{floor: 2, direction: :stop, behavior: :door_open}
    assert Orders.should_clear_immediately?(door_open_stop, 2, :hall_down)
  end
end
