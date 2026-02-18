defmodule SingleElevatorTest do
  use ExUnit.Case
  # TODO: Maybe doctest
  # doctest Elevator

  @tag :hall_orders_single
  test "initializes state with unknown values" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert map_size(state) == 4
    assert state[{0, :hall_up}] == :unknown
    assert state[{1, :hall_up}] == :unknown
    assert state[{1, :hall_down}] == :unknown
    assert state[{2, :hall_down}] == :unknown
  end

  @tag :hall_orders_single
  test "button press puts single elevator confirmed state" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert {:noreply, final_state} = hallorder_cast_full({:button_press, 0, :hall_up}, state)
    assert {:confirmed, _, _} = final_state[{0, :hall_up}]
  end

  @tag :hall_orders_single
  test "arrive at floor from confirmed state puts elevator in idle state" do
    {:ok, state} = Elevator.HallOrders.init(3)
    id = Node.self()
    state = Map.put(state, {1, :hall_down}, {:confirmed, %{id => 5}, MapSet.new([id])})
    assert {:noreply, final_state} = hallorder_cast_full({:arrived_at_floor, 1, :down}, state)
    assert :idle = final_state[{1, :hall_down}]
  end

  @tag :hall_orders_single
  test "clear floor from pending state leaves elevator state unchanged" do
    {:ok, state} = Elevator.HallOrders.init(3)
    id = Node.self()
    state = Map.put(state, {1, :hall_up}, {:pending, MapSet.new([id])})
    assert {:noreply, final_state} = hallorder_cast_full({:arrived_at_floor, 1, :up}, state)
    assert {:pending, _} = final_state[{1, :hall_up}]
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
