defmodule Test.Single.DecisionTest do
  use ExUnit.Case, async: true

  alias Elevator.Decision

  test "unknonw floor, :down -> stop,idle" do
    orders = %{}
    state = %Elevator.State{floor: :unknown, direction: :down}
    assert Decision.next_action(orders, state) == {:stop, :idle}
  end

  test "no requests -> stop,idle" do
    orders = %{}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Decision.next_action(orders, state) == {:stop, :idle}
  end

  test "nearest above -> up,moving" do
    orders = %{3 => MapSet.new([:cab]), 4 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Decision.next_action(orders, state) == {:up, :moving}
  end

  test "nearest below -> down,moving" do
    orders = %{0 => MapSet.new([:cab]), 2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 3, direction: :stop}
    assert Decision.next_action(orders, state) == {:down, :moving}
  end

  test "cab above -> up,moving" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 1, direction: :down}
    assert Decision.next_action(orders, state) == {:up, :moving}
  end

  test "same floor cab -> stop,door_open" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.State{floor: 2, direction: :stop}
    assert Decision.next_action(orders, state) == {:stop, :door_open}
  end

  test "same floor hall_up -> up,door_open" do
    orders = %{1 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Decision.next_action(orders, state) == {:up, :door_open}
  end

  test "same floor hall_down -> down,door_open" do
    orders = %{1 => MapSet.new([:hall_down])}
    state = %Elevator.State{floor: 1, direction: :stop}
    assert Decision.next_action(orders, state) == {:down, :door_open}
  end

  test "same floor hall_up while moving up -> up,door_open" do
    orders = %{1 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :up}
    assert Decision.next_action(orders, state) == {:up, :door_open}
  end

  test "same floor hall_down while moving down -> down,door_open" do
    orders = %{1 => MapSet.new([:hall_down])}
    state = %Elevator.State{floor: 1, direction: :down}
    assert Decision.next_action(orders, state) == {:down, :door_open}
  end

  test "same floor cab with requests above while moving up -> up,door_open" do
    orders = %{1 => MapSet.new([:cab]), 3 => MapSet.new([:hall_up])}
    state = %Elevator.State{floor: 1, direction: :up}
    assert Decision.next_action(orders, state) == {:up, :door_open}
  end

  test "should_clear_immediately?" do
    door_open_up = %Elevator.State{floor: 2, direction: :up, behavior: :door_open}

    assert Decision.should_clear_immediately?(door_open_up, 2, :cab)
    assert Decision.should_clear_immediately?(door_open_up, 2, :hall_up)

    refute Decision.should_clear_immediately?(door_open_up, 2, :hall_down)
    refute Decision.should_clear_immediately?(door_open_up, 3, :cab)

    moving = %Elevator.State{floor: 2, direction: :up, behavior: :moving}
    assert Decision.should_clear_immediately?(moving, 2, :cab)

    door_open_stop = %Elevator.State{floor: 2, direction: :stop, behavior: :door_open}
    assert Decision.should_clear_immediately?(door_open_stop, 2, :hall_down)
  end
end
