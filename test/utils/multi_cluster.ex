defmodule Test.Utils.MultiCluster do
  @moduledoc false

  @node_shutdown_timeout_ms 1000
  @cluster_wait_timeout_ms 2000
  @poll_interval_ms 50

  @spec start_three_node_cluster(non_neg_integer(), boolean()) :: %{
          nodes: [node()],
          peers: [pid()]
        }
  def start_three_node_cluster(num_floors, communicator_resend) do
    {peer1, node1} = start_and_wait_for_node(:elev1, num_floors, communicator_resend)
    {peer2, node2} = start_and_wait_for_node(:elev2, num_floors, communicator_resend)

    :erpc.call(Node.self(), Test.Utils.TestCompiled, :start_order_modules, [
      num_floors,
      communicator_resend
    ])

    :erpc.call(node1, Node, :connect, [node2])

    %{nodes: [node1, node2, Node.self()], peers: [peer1, peer2]}
  end

  @spec stop_three_node_cluster(%{nodes: [node()], peers: [pid()]}) :: :ok
  def stop_three_node_cluster(%{nodes: [node1, node2, _self], peers: [peer1, peer2]}) do
    stop_local_supervisor()

    Node.disconnect(node1)
    Node.disconnect(node2)

    stop_peer(peer1)
    stop_peer(peer2)

    wait_until_disconnected([node1, node2])
    :ok
  end

  defp stop_local_supervisor do
    if pid = Process.whereis(Elevator.Supervisor) do
      if Process.alive?(pid) do
        Process.monitor(pid)

        try do
          Supervisor.stop(pid)
        catch
          :exit, _ -> :ok
        end

        receive do
          {:DOWN, _, :process, ^pid, _} -> :ok
        after
          @node_shutdown_timeout_ms -> :ok
        end
      end
    end
  end

  defp stop_peer(peer) do
    try do
      :peer.stop(peer)
    catch
      :exit, _ -> :ok
    end
  end

  defp start_and_wait_for_node(name, num_floors, communicator_resend) do
    cookie = Atom.to_charlist(Node.get_cookie())

    {peer, node} =
      case :peer.start_link(%{name: name, longnames: false, args: [~c"-setcookie", cookie]}) do
        {:ok, peer, node} ->
          {peer, node}

        {:ok, peer} ->
          {peer, :peer.call(peer, :erlang, :node, [])}

        {:error, reason} ->
          raise "Failed to start peer node: #{inspect(reason)}"
      end

    wait_until_connected([node])
    :rpc.call(node, :code, :add_paths, [:code.get_path()])

    :erpc.call(node, Test.Utils.TestCompiled, :start_order_modules, [
      num_floors,
      communicator_resend
    ])

    {peer, node}
  end

  defp wait_until_connected(nodes, timeout \\ @cluster_wait_timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_connected_loop(nodes, deadline)
  end

  defp wait_until_disconnected(nodes, timeout \\ @cluster_wait_timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_disconnected_loop(nodes, deadline)
  end

  defp wait_connected_loop(nodes, deadline) do
    if Enum.all?(nodes, fn node -> node in Node.list(:connected) end) do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        raise "Test timed out waiting for nodes"
      end

      Process.sleep(@poll_interval_ms)
      wait_connected_loop(nodes, deadline)
    end
  end

  defp wait_disconnected_loop(nodes, deadline) do
    if Enum.all?(nodes, fn node -> node not in Node.list(:connected) end) do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        raise "Test timed out waiting for node disconnect"
      end

      Process.sleep(@poll_interval_ms)
      wait_disconnected_loop(nodes, deadline)
    end
  end
end
