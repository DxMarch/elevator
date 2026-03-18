defmodule Test.Single.DecisionTest do
  use ExUnit.Case, async: true

  alias Elevator.Decision

  test "unknown floor, :down -> down,idle" do
    orders = %{}
    state = %Elevator.FSM.State{floor: :unknown, direction: :down, between_floors: false}
    assert Decision.next_action(orders, state) == {:down, :idle}
  end

  test "no requests -> keep direction,idle" do
    orders = %{}
    state = %Elevator.FSM.State{floor: 1, direction: :up, between_floors: false}
    assert Decision.next_action(orders, state) == {:up, :idle}
  end

  test "nearest above -> up,moving" do
    orders = %{3 => MapSet.new([:cab]), 4 => MapSet.new([:hall_up])}
    state = %Elevator.FSM.State{floor: 1, direction: :up, between_floors: false}
    assert Decision.next_action(orders, state) == {:up, :moving}
  end

  test "nearest below -> down,moving" do
    orders = %{0 => MapSet.new([:cab]), 2 => MapSet.new([:cab])}
    state = %Elevator.FSM.State{floor: 3, direction: :down, between_floors: false}
    assert Decision.next_action(orders, state) == {:down, :moving}
  end

  test "cab above -> up,moving" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.FSM.State{floor: 1, direction: :down, between_floors: false}
    assert Decision.next_action(orders, state) == {:up, :moving}
  end

  test "same floor cab while moving up -> up,door_open" do
    orders = %{2 => MapSet.new([:cab])}
    state = %Elevator.FSM.State{floor: 2, direction: :up, between_floors: false}
    assert Decision.next_action(orders, state) == {:up, :door_open}
  end

  test "same floor hall_up while idle up -> up,door_open" do
    orders = %{1 => MapSet.new([:hall_up])}
    state = %Elevator.FSM.State{floor: 1, direction: :up, between_floors: false}
    assert Decision.next_action(orders, state) == {:up, :door_open}
  end

  test "same floor hall_down while idle down -> down,door_open" do
    orders = %{1 => MapSet.new([:hall_down])}
    state = %Elevator.FSM.State{floor: 1, direction: :down, between_floors: false}
    assert Decision.next_action(orders, state) == {:down, :door_open}
  end

  test "same floor hall_up while moving up -> up,door_open" do
    orders = %{1 => MapSet.new([:hall_up])}
    state = %Elevator.FSM.State{floor: 1, direction: :up, between_floors: false}
    assert Decision.next_action(orders, state) == {:up, :door_open}
  end

  test "same floor hall_down while moving down -> down,door_open" do
    orders = %{1 => MapSet.new([:hall_down])}
    state = %Elevator.FSM.State{floor: 1, direction: :down, between_floors: false}
    assert Decision.next_action(orders, state) == {:down, :door_open}
  end

  test "same floor cab with requests above while moving up -> up,door_open" do
    orders = %{1 => MapSet.new([:cab]), 3 => MapSet.new([:hall_up])}
    state = %Elevator.FSM.State{floor: 1, direction: :up, between_floors: false}
    assert Decision.next_action(orders, state) == {:up, :door_open}
  end
end
