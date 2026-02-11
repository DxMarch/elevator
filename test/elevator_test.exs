defmodule ElevatorTest do
  use ExUnit.Case
  doctest Elevator

  @tag :hall_orders
  test "initializes state with unknown values" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert map_size(state) == 4
    assert state[{0, :up}] == :unknown
    assert state[{1, :up}] == :unknown
    assert state[{1, :down}] == :unknown
    assert state[{2, :down}] == :unknown
  end
end
