defmodule Test.Multi.HallOrdersTest do
  alias Elevator.HallOrders
  alias Elevator.Communicator
  alias Test.Utils.MultiCluster
  alias Test.Utils.TestCompiled, as: TestUtils
  use ExUnit.Case, async: false

  setup context do
    communicator_resend = not Map.get(context, :manual_sending, false)

    cluster = MultiCluster.start_three_node_cluster(Elevator.num_floors(), communicator_resend)

    on_exit(fn ->
      MultiCluster.stop_three_node_cluster(cluster)
    end)

    {:ok, nodes: cluster.nodes}
  end

  test "test runner self-acceptance" do
    assert MapSet.size(Communicator.who_can_serve()) == 3
  end

  @tag :manual_sending
  test "button convergence to confirmed", %{nodes: [node1, node2, node3]} do
    # Node 1 gets a button call
    :rpc.call(node1, HallOrders, :button_press, [0, :hall_up])
    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    assert {:pending, _} = node1_state[{0, :hall_up}]

    # Node 1 sends their orders to node 2
    assert :rpc.call(node2, HallOrders, :receive_external, [node1_state]) == :ok
    node2_state = :rpc.call(node2, HallOrders, :get_order_map, [])
    assert {:pending, barrier2} = node2_state[{0, :hall_up}]

    assert MapSet.member?(barrier2, node1)
    assert MapSet.member?(barrier2, node2)
    assert not MapSet.member?(barrier2, node3)

    # Node 1 sends their orders to node 3
    assert :rpc.call(node3, HallOrders, :receive_external, [node1_state]) == :ok
    node3_state = :rpc.call(node3, HallOrders, :get_order_map, [])
    assert {:pending, barrier3} = node3_state[{0, :hall_up}]

    assert MapSet.member?(barrier3, node1)
    assert MapSet.member?(barrier3, node3)
    assert not MapSet.member?(barrier3, node2)

    # Node 1 receives orders from both 2 and 3
    assert :rpc.call(node1, HallOrders, :receive_external, [node2_state]) == :ok
    assert :rpc.call(node1, HallOrders, :receive_external, [node3_state]) == :ok

    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    assert {:handling, _} = node1_state[{0, :hall_up}]

    clique_exchange_states([node1, node2, node3])

    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    node2_state = :rpc.call(node2, HallOrders, :get_order_map, [])
    node3_state = :rpc.call(node3, HallOrders, :get_order_map, [])

    # All should have converged on the alive set
    assert node1_state == node2_state and node2_state == node3_state
    assert {:handling, _} = node1_state[{0, :hall_up}]
    converged_state = node1_state

    # ... so another exchange run should not affect the result
    clique_exchange_states([node1, node2, node3])

    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    node2_state = :rpc.call(node2, HallOrders, :get_order_map, [])
    node3_state = :rpc.call(node3, HallOrders, :get_order_map, [])

    assert node1_state == converged_state and node1_state == node2_state and
             node2_state == node3_state
  end

  @tag :manual_sending
  test "button -> arrived convergence to idle", %{nodes: [node1, node2, node3] = nodes} do
    :rpc.call(node2, HallOrders, :button_press, [1, :hall_down])
    clique_exchange_states(nodes)
    clique_exchange_states(nodes)

    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    assert {:handling, _} = node1_state[{1, :hall_down}]

    # Assume node3 arrives at the floor
    :rpc.call(node3, HallOrders, :arrived_at_floor, [1, :down])

    clique_exchange_states(nodes)

    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    node2_state = :rpc.call(node2, HallOrders, :get_order_map, [])
    node3_state = :rpc.call(node3, HallOrders, :get_order_map, [])

    assert :idle = node1_state[{1, :hall_down}]
    assert :idle = node2_state[{1, :hall_down}]
    assert :idle = node3_state[{1, :hall_down}]
  end

  @tag :manual_sending
  test "all agree on who serves the order", %{nodes: [node1, node2, node3] = nodes} do
    :rpc.call(node2, HallOrders, :button_press, [2, :hall_up])
    clique_exchange_states(nodes)
    clique_exchange_states(nodes)

    node1_orders = :rpc.call(node1, HallOrders, :get_my_orders, [])
    node2_orders = :rpc.call(node2, HallOrders, :get_my_orders, [])
    node3_orders = :rpc.call(node3, HallOrders, :get_my_orders, [])

    assert map_size(node1_orders) + map_size(node2_orders) + map_size(node3_orders) == 1
  end

  test "communicator causes convergence", %{nodes: [node1, node2, node3]} do
    :rpc.call(node1, HallOrders, :button_press, [2, :hall_up])

    Process.sleep(TestUtils.convergence_wait_ms())

    node1_orders = :rpc.call(node1, HallOrders, :get_my_orders, [])
    node2_orders = :rpc.call(node2, HallOrders, :get_my_orders, [])
    node3_orders = :rpc.call(node3, HallOrders, :get_my_orders, [])

    assert map_size(node1_orders) + map_size(node2_orders) + map_size(node3_orders) == 1

    who_arrives =
      cond do
        map_size(node1_orders) == 1 ->
          node1

        map_size(node2_orders) == 1 ->
          node2

        map_size(node3_orders) == 1 ->
          node3
      end

    :rpc.call(who_arrives, HallOrders, :arrived_at_floor, [2, :up])

    Process.sleep(TestUtils.convergence_wait_ms())

    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    node2_state = :rpc.call(node2, HallOrders, :get_order_map, [])
    node3_state = :rpc.call(node3, HallOrders, :get_order_map, [])

    assert node1_state == node2_state and node2_state == node3_state
    assert :idle = node1_state[{2, :hall_up}]
  end

  defp clique_exchange_states([node1, node2, node3]) do
    # 1 -> 2
    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    assert :rpc.call(node2, HallOrders, :receive_external, [node1_state])

    # 2 -> 3
    node2_state = :rpc.call(node2, HallOrders, :get_order_map, [])
    assert :rpc.call(node3, HallOrders, :receive_external, [node2_state])

    # 3 -> 1
    node3_state = :rpc.call(node3, HallOrders, :get_order_map, [])
    assert :rpc.call(node1, HallOrders, :receive_external, [node3_state])

    # 1 -> 2, 3
    node1_state = :rpc.call(node1, HallOrders, :get_order_map, [])
    assert :rpc.call(node2, HallOrders, :receive_external, [node1_state])
    assert :rpc.call(node3, HallOrders, :receive_external, [node1_state])

    # 2 -> 1, 3
    node2_state = :rpc.call(node2, HallOrders, :get_order_map, [])
    assert :rpc.call(node1, HallOrders, :receive_external, [node2_state])
    assert :rpc.call(node3, HallOrders, :receive_external, [node2_state])

    # 3 -> 1, 2
    node3_state = :rpc.call(node3, HallOrders, :get_order_map, [])
    assert :rpc.call(node1, HallOrders, :receive_external, [node3_state])
    assert :rpc.call(node2, HallOrders, :receive_external, [node3_state])

    # Yay!
  end
end
