defmodule Test.Multi.HallOrders do
  alias Elevator.HallOrders
  alias Elevator.Communicator
  use ExUnit.Case, async: false

  setup do
    {_, node1} = start_and_wait_for_node(:elev1)
    {_, node2} = start_and_wait_for_node(:elev2)

    :erpc.call(Node.self(), Elevator.Support.TestCompiled, :start_order_modules, [Elevator.num_floors()])

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

  test "test runner self-acceptance" do
    assert MapSet.size(Communicator.who_is_alive()) == 3
  end

  test "button convergence to confirmed", %{nodes: [node1, node2, node3]} do
    # Node 1 gets a button call
    :rpc.call(node1, HallOrders, :button_press, [0, :hall_up])
    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    assert {:pending, _} = node1_state[{0, :hall_up}]

    # Node 1 sends their orders to node 2
    assert :rpc.call(node2, HallOrders, :receive_state, [node1_state]) == :ok
    node2_state = :rpc.call(node2, HallOrders, :get_state, [])
    assert {:pending, barrier2} = node2_state[{0, :hall_up}]

    assert MapSet.member?(barrier2, node1)
    assert MapSet.member?(barrier2, node2)
    assert not MapSet.member?(barrier2, node3)

    # Node 1 sends their orders to node 3
    assert :rpc.call(node3, HallOrders, :receive_state, [node1_state]) == :ok
    node3_state = :rpc.call(node3, HallOrders, :get_state, [])
    assert {:pending, barrier3} = node3_state[{0, :hall_up}]

    assert MapSet.member?(barrier3, node1)
    assert MapSet.member?(barrier3, node3)
    assert not MapSet.member?(barrier3, node2)

    # Node 1 receives orders from both 2 and 3
    assert :rpc.call(node1, HallOrders, :receive_state, [node2_state]) == :ok
    assert :rpc.call(node1, HallOrders, :receive_state, [node3_state]) == :ok

    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    assert {:confirmed, _, _} = node1_state[{0, :hall_up}]

    clique_exchange_states([node1, node2, node3])

    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    node2_state = :rpc.call(node2, HallOrders, :get_state, [])
    node3_state = :rpc.call(node3, HallOrders, :get_state, [])

    # All should have converged on the alive set
    assert node1_state == node2_state and node2_state == node3_state
    alive = Communicator.who_is_alive()
    assert {:confirmed, _, ^alive} = node1_state[{0, :hall_up}]
    converged_state = node1_state

    # ... so another exchange run should not affect the result
    clique_exchange_states([node1, node2, node3])

    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    node2_state = :rpc.call(node2, HallOrders, :get_state, [])
    node3_state = :rpc.call(node3, HallOrders, :get_state, [])

    assert node1_state == converged_state and node1_state == node2_state and node2_state == node3_state
  end

  test "button -> arrived convergence to idle", %{nodes: [node1, node2, node3] = nodes} do
    :rpc.call(node2, HallOrders, :button_press, [1, :hall_down])
    clique_exchange_states(nodes)
    clique_exchange_states(nodes)

    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    assert {:confirmed, _, _} = node1_state[{1, :hall_down}]

    # Assume node3 arrives at the floor
    :rpc.call(node3, HallOrders, :arrived_at_floor, [1, :down])

    clique_exchange_states(nodes)

    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    node2_state = :rpc.call(node2, HallOrders, :get_state, [])
    node3_state = :rpc.call(node3, HallOrders, :get_state, [])

    assert node1_state[{1, :hall_down}] == :idle
    assert node2_state[{1, :hall_down}] == :idle
    assert node3_state[{1, :hall_down}] == :idle
  end

  defp clique_exchange_states([node1, node2, node3]) do
    # 1 -> 2
    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    assert :rpc.call(node2, HallOrders, :receive_state, [node1_state])

    # 2 -> 3
    node2_state = :rpc.call(node2, HallOrders, :get_state, [])
    assert :rpc.call(node3, HallOrders, :receive_state, [node2_state])

    # 3 -> 1
    node3_state = :rpc.call(node3, HallOrders, :get_state, [])
    assert :rpc.call(node1, HallOrders, :receive_state, [node3_state])

    # 1 -> 2, 3
    node1_state = :rpc.call(node1, HallOrders, :get_state, [])
    assert :rpc.call(node2, HallOrders, :receive_state, [node1_state])
    assert :rpc.call(node3, HallOrders, :receive_state, [node1_state])

    # 2 -> 1, 3
    node2_state = :rpc.call(node2, HallOrders, :get_state, [])
    assert :rpc.call(node1, HallOrders, :receive_state, [node2_state])
    assert :rpc.call(node3, HallOrders, :receive_state, [node2_state])

    # 3 -> 1, 2
    node3_state = :rpc.call(node3, HallOrders, :get_state, [])
    assert :rpc.call(node1, HallOrders, :receive_state, [node3_state])
    assert :rpc.call(node2, HallOrders, :receive_state, [node3_state])

    # Yay?
  end

  defp start_and_wait_for_node(name) do
    {:ok, peer, node} = :peer.start_link(%{
      name: name, 
      name_domain: :shortnames
    })

    wait_until_connected([node])
    :rpc.call(node, :code, :add_paths, [:code.get_path()])
    :erpc.call(node, Elevator.Support.TestCompiled, :start_order_modules, [Elevator.num_floors()])
    {peer, node}
  end

  defp wait_until_connected(nodes, timeout \\ 2000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_loop(nodes, deadline)
  end

  defp wait_loop(nodes, deadline) do
    if Enum.all?(nodes, fn node -> MapSet.member?(Communicator.who_is_alive(), node) end) do
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
