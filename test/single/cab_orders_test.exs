defmodule Test.Single.CabOrdersTest do
  alias Elevator.Communicator
  alias Elevator.CabOrders
  use ExUnit.Case, async: false

  setup_all do
    children = [
      {Elevator.HallOrders, Elevator.num_floors()},
      Elevator.Communicator,
      Elevator.CabOrders,
    ]
    opts = [strategy: :one_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
    :ok
  end

  test "cab orders module starts without orders" do
    {:ok, state} = CabOrders.init()
    {:reply, orders, _} = CabOrders.handle_call(:get_my_orders, Node.self(), state)
    assert MapSet.size(orders) == 0
  end

  test "button press creates a cab order" do
    {:ok, state} = CabOrders.init()
    assert {:noreply, state} = CabOrders.handle_cast({:button_press, 1}, state)
    {:reply, orders, _} = CabOrders.handle_call(:get_my_orders, Node.self(), state)
    assert MapSet.size(orders) == 1
    assert MapSet.member?(orders, 1)
  end

  test "arrived at floor deletes cab order" do
    {:ok, state} = CabOrders.init()
    state = Map.update(state, Communicator.my_id(), Communicator.my_id(), fn _old -> %{version: 1, orders: MapSet.new([1])} end)
    {:reply, orders, _} = CabOrders.handle_call(:get_my_orders, Node.self(), state)
    assert MapSet.size(orders) == 1

    # Arrival at second floor should have no impact
    assert {:noreply, state} = CabOrders.handle_cast({:arrived_at_floor, 2}, state)
    {:reply, orders, _} = CabOrders.handle_call(:get_my_orders, Node.self(), state)
    assert MapSet.size(orders) == 1
    assert MapSet.member?(orders, 1)

    #Arrival at first floor should clear it from the set
    assert {:noreply, state} = CabOrders.handle_cast({:arrived_at_floor, 1}, state)
    {:reply, orders, _} = CabOrders.handle_call(:get_my_orders, Node.self(), state)
    assert MapSet.size(orders) == 0
  end

  test "version number increments correctly" do
    {:ok, state} = CabOrders.init()
    assert state[Communicator.my_id()].version == 0
    assert {:noreply, state} = CabOrders.handle_cast({:arrived_at_floor, 1}, state)
    assert state[Communicator.my_id()].version == 1
    assert {:noreply, state} = CabOrders.handle_cast({:button_press, 1}, state)
    assert state[Communicator.my_id()].version == 2
    assert {:noreply, state} = CabOrders.handle_cast({:button_press, 1}, state)
    assert state[Communicator.my_id()].version == 3
  end

end
