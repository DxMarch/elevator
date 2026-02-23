defmodule Test.Single.CabOrdersTest do
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

  # TODO: Some more tests?
end
