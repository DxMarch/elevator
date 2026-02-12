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

  @tag :hall_orders
  test "button press puts single elevator confirmed state" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert {:noreply, final_state} = hallorder_cast_full({:button_press, 0, :up}, state)
    assert {:confirmed, _, _} = final_state[{0, :up}]
  end

  @tag :hall_orders
  test "arrive at floor from confirmed state puts elevator in idle state" do
    {:ok, state} = Elevator.HallOrders.init(3)
    id = Node.self()
    state = Map.put(state, {1, :down}, {:confirmed, %{id => 5}, MapSet.new([id])})
    assert {:noreply, final_state} = hallorder_cast_full({:arrived_at_floor, 1, :down}, state)
    assert :idle = final_state[{1, :down}]
  end

  @tag :hall_orders
  test "clear floor from pending state leaves elevator state unchanged" do
    {:ok, state} = Elevator.HallOrders.init(3)
    id = Node.self()
    state = Map.put(state, {1, :up}, {:pending, MapSet.new([id])})
    assert {:noreply, final_state} = hallorder_cast_full({:arrived_at_floor, 1, :up}, state)
    assert {:pending, _} = final_state[{1, :up}]
  end

  defp hallorder_cast_full(msg, state) do
    ret = Elevator.HallOrders.handle_cast(msg, state)

    case ret do
      {:noreply, new_state, {:continue, continue_arg}} ->
        hallorder_continue_full(continue_arg, new_state)
      _ ->
        ret
    end
  end

  defp hallorder_continue_full(continue_arg, state, continue_counter \\ 0) do
    # Prevent infinite continue loop
    assert continue_counter < 100

    ret = Elevator.HallOrders.handle_continue(continue_arg, state)

    case ret do
      {:noreply, new_state, {:continue, continue_arg}} ->
        hallorder_continue_full(continue_arg, new_state, continue_counter + 1)
      _ ->
        ret
    end
  end
end
