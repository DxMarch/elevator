defmodule Test.Multi.CabOrdersTest do
  alias Elevator.CabOrders

  use ExUnit.Case, async: false

  setup ctx do
    communicator_resend = not Map.get(ctx, :manual_sending, false)

    {_, node1} = start_and_wait_for_node(:elev1, communicator_resend)
    {_, node2} = start_and_wait_for_node(:elev2, communicator_resend)

    :erpc.call(Node.self(), Test.Utils.TestCompiled, :start_order_modules, [
      Elevator.num_floors(),
      communicator_resend
    ])

    # Make a clique
    :erpc.call(node1, Node, :connect, [node2])

    on_exit(fn ->
      # Stop own supervisor
      if pid = Process.whereis(Elevator.Supervisor) do
        Process.monitor(pid)
        Supervisor.stop(pid)
        # Wait for it to actually be gone before next test starts
        receive do
          {:DOWN, _, :process, ^pid, _} -> :ok
        after
          1000 -> :ok
        end
      end
    end)

    {:ok, nodes: [node1, node2, Node.self()]}
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

    Process.sleep(3 * Elevator.resend_period())

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

    Process.sleep(3 * Elevator.resend_period())

    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    assert node1_version == 69
    assert node1_orders == MapSet.new([1])

    # Lower version number should be ignored
    :rpc.cast(node3, CabOrders, :receive_state, [
      %{node1 => %{version: 67, orders: MapSet.new([1, 2])}}
    ])

    Process.sleep(3 * Elevator.resend_period())

    %{version: node1_version, orders: node1_orders} =
      :rpc.call(node1, CabOrders, :get_state, [])[node1]

    assert node1_version == 69
    assert node1_orders == MapSet.new([1])

    # Same version number should be ignored
    :rpc.cast(node3, CabOrders, :receive_state, [
      %{node1 => %{version: 69, orders: MapSet.new([1, 2])}}
    ])

    Process.sleep(3 * Elevator.resend_period())

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
    Process.sleep(3 * Elevator.resend_period())

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

  def start_and_wait_for_node(name, communicator_resend) do
    {:ok, peer, node} =
      :peer.start_link(%{
        name: name,
        name_domain: :shortnames
      })

    wait_until_connected([node])
    :rpc.call(node, :code, :add_paths, [:code.get_path()])

    :erpc.call(node, Test.Utils.TestCompiled, :start_order_modules, [
      Elevator.num_floors(),
      communicator_resend
    ])

    {peer, node}
  end

  defp wait_until_connected(nodes, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_loop(nodes, deadline)
  end

  defp wait_loop(nodes, deadline) do
    if Enum.all?(nodes, fn node -> node in Node.list(:connected) end) do
      true
    else
      if System.monotonic_time(:millisecond) > deadline do
        flunk("Test timed out waiting for nodes")
      end

      Process.sleep(50)
      wait_loop(nodes, deadline)
    end
  end
end
