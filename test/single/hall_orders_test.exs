defmodule Test.Single.HallOrdersTest do
  use ExUnit.Case, async: false
  # TODO: Maybe doctest

  setup_all do
    start_supervised!(Elevator.Communicator)
    start_supervised!(Elevator.CabOrders)
    start_supervised!({Elevator.HallOrders, Elevator.num_floors()})
    start_supervised!(Elevator.FSM.State)
    :ok
  end

  @tag :hall_orders_single
  test "initializes state with idle values" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert map_size(state) == 4
    assert :idle = state[{0, :hall_up}]
    assert :idle = state[{1, :hall_up}]
    assert :idle = state[{1, :hall_down}]
    assert :idle = state[{2, :hall_down}]
  end

  @tag :hall_orders_single
  test "button press puts single elevator confirmed state" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert {:noreply, final_state} = hallorder_cast_full({:button_press, 0, :hall_up}, state)
    assert {:handling, _} = final_state[{0, :hall_up}]
  end

  @tag :hall_orders_single
  test "arrive at floor from confirmed state puts elevator in idle state" do
    {:ok, state} = Elevator.HallOrders.init(3)
    id = Node.self()
    state = Map.put(state, {1, :hall_down}, {:handling, %{id => 5}})
    assert {:noreply, final_state} = hallorder_cast_full({:arrived_at_floor, 1, :down}, state)
    assert :idle = final_state[{1, :hall_down}]
  end

  @tag :hall_orders_single
  test "clear floor from pending state should not put order in idle" do
    {:ok, state} = Elevator.HallOrders.init(3)
    id = Node.self()
    state = Map.put(state, {1, :hall_up}, {:pending, MapSet.new([id])})
    assert {:noreply, final_state} = hallorder_cast_full({:arrived_at_floor, 1, :up}, state)
    assert {:handling, _} = final_state[{1, :hall_up}]
  end

  @tag :hall_orders_single
  test "clear floor from other direction leaves elevator state unchanged" do
    {:ok, state} = Elevator.HallOrders.init(3)
    id = Node.self()
    state = Map.put(state, {1, :hall_up}, {:handling, %{id => 5}})
    assert {:noreply, final_state} = hallorder_cast_full({:arrived_at_floor, 1, :down}, state)
    assert {:handling, _} = final_state[{1, :hall_up}]
  end

  @tag :hall_orders_single
  test "initial elevator has no orders" do
    {:ok, state} = Elevator.HallOrders.init(3)
    {:reply, orders, _} = Elevator.HallOrders.handle_call(:get_my_orders, nil, state)
    assert Enum.count(orders) == 0
  end

  @tag :hall_orders_single
  test "elevator get_my_orders returns confirmed orders" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert {:noreply, final_state} = hallorder_cast_full({:button_press, 0, :hall_up}, state)
    {:reply, orders, _} = Elevator.HallOrders.handle_call(:get_my_orders, nil, final_state)
    assert Enum.count(orders) == 1
    assert Map.has_key?(orders, 0)
    assert orders[0] == MapSet.new([:hall_up])
  end

  @tag :hall_orders_single
  test "elevator get_my_orders can return both hall_up and hall_down orders" do
    {:ok, state} = Elevator.HallOrders.init(3)
    assert {:noreply, state} = hallorder_cast_full({:button_press, 1, :hall_up}, state)
    assert {:noreply, state} = hallorder_cast_full({:button_press, 1, :hall_down}, state)
    {:reply, orders, _} = Elevator.HallOrders.handle_call(:get_my_orders, nil, state)
    assert Enum.count(orders) == 1
    assert Map.has_key?(orders, 1)
    assert orders[1] == MapSet.new([:hall_up, :hall_down])
  end

  defp hallorder_cast_full(msg, state) do
    ret = Elevator.HallOrders.handle_cast(msg, state)

    case ret do
      {:noreply, new_state, {:continue, continue_arg}} ->
        Elevator.HallOrders.handle_continue(continue_arg, new_state)

      _ ->
        ret
    end
  end
end
