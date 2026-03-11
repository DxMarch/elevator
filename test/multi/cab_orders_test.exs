defmodule Test.Multi.CabOrdersTest do
  alias Elevator.CabOrders
  alias Test.Utils.MultiCluster

  use ExUnit.Case, async: false

  setup context do
    communicator_resend = not Map.get(context, :manual_sending, false)

    cluster = MultiCluster.start_three_node_cluster(Elevator.num_floors(), communicator_resend)

    on_exit(fn ->
      MultiCluster.stop_three_node_cluster(cluster)
    end)

    {:ok, nodes: cluster.nodes}
  end

  test "cab orders are private", %{nodes: [node1, node2, node3]} do
    :rpc.call(node1, CabOrders, :button_press, [1])
    :rpc.call(node2, CabOrders, :button_press, [2])
    :rpc.call(node3, CabOrders, :button_press, [3])

    node1_orders = :rpc.call(node1, CabOrders, :get_my_orders, [])
    node2_orders = :rpc.call(node2, CabOrders, :get_my_orders, [])
    node3_orders = :rpc.call(node3, CabOrders, :get_my_orders, [])

    assert node1_orders == MapSet.new([1])
    assert node2_orders == MapSet.new([2])
    assert node3_orders == MapSet.new([3])
  end

  test "elevator recovers cab orders", %{nodes: [node1, node2, _node3]} do
    node1_orders = :rpc.call(node1, CabOrders, :get_my_orders, [])
    assert node1_orders == MapSet.new()

    :rpc.call(node2, CabOrders, :receive_state, [
      %{node1 => %{version: 420, orders: MapSet.new([3])}}
    ])

    Process.sleep(Elevator.test_convergence_wait_time())

    node1_orders = :rpc.call(node1, CabOrders, :get_my_orders, [])
    assert node1_orders == MapSet.new([3])
  end

  test "elevator ingores lower version numbers", %{nodes: [node1, node2, node3]} do
    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    assert node1_version == 0
    assert node1_orders == MapSet.new()

    # Higher version number should overwrite
    :rpc.cast(node2, CabOrders, :receive_state, [
      %{node1 => %{version: 69, orders: MapSet.new([1])}}
    ])

    Process.sleep(Elevator.test_convergence_wait_time())

    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    assert node1_version == 69
    assert node1_orders == MapSet.new([1])

    # Lower version number should be ignored
    :rpc.cast(node3, CabOrders, :receive_state, [
      %{node1 => %{version: 67, orders: MapSet.new([1, 2])}}
    ])

    Process.sleep(Elevator.test_convergence_wait_time())

    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    assert node1_version == 69
    assert node1_orders == MapSet.new([1])

    # Same version number should be ignored
    :rpc.cast(node3, CabOrders, :receive_state, [
      %{node1 => %{version: 69, orders: MapSet.new([1, 2])}}
    ])

    Process.sleep(Elevator.test_convergence_wait_time())

    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    assert node1_version == 69
    assert node1_orders == MapSet.new([1])
  end

  test "cab order states progate", %{nodes: [node1, node2, node3]} do
    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    %{version: node2_version, orders: node2_orders} =
      :rpc.call(node2, CabOrders, :get_state, [])[node2]

    %{version: node3_version, orders: node3_orders} =
      :rpc.call(node3, CabOrders, :get_state, [])[node3]

    assert node1_version == 0 and node2_version == 0 and node3_version == 0

    assert node1_orders == MapSet.new() and node2_orders == MapSet.new() and
             node3_orders == MapSet.new()

    :rpc.cast(node1, CabOrders, :button_press, [1])
    Process.sleep(Elevator.test_convergence_wait_time())

    # Ensure that node1's version and order map has propagated across all nodes
    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    assert node1_version == 1
    assert MapSet.member?(node1_orders, 1)

    node1_state = :rpc.call(node1, CabOrders, :get_state, [])
    node2_state = :rpc.call(node2, CabOrders, :get_state, [])
    node3_state = :rpc.call(node3, CabOrders, :get_state, [])

    assert Map.equal?(node1_state, node2_state)
    assert Map.equal?(node2_state, node3_state)
  end
end
