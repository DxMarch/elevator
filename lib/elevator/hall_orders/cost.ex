defmodule Elevator.HallOrders.Cost do
  alias Elevator.CabOrders
  require Logger

  @doc """
  Maybe even random numbers?
  """
  def compute_cost({floor, btn_dir}, my_hall_orders) do
    state = Elevator.FSM.State.get_state()

    cab_orders = CabOrders.get_my_orders()

    payload_map =
      state_and_orders_to_external_format({floor, btn_dir}, state, cab_orders, my_hall_orders)

    try do
      json_input = JSON.encode!(payload_map)
      {output, 0} = System.cmd(Elevator.time_to_serve_executable(), ["-i", json_input])
      String.to_integer(String.trim(output))
    rescue
      _ ->
        30000
    end
  end

  @doc """
  Merge two cost maps. 
  Uses pessimistic merge: If two conflicting costs for the same node are found, keep the higher one.
  """
  def merge_cost(cost_map_1, cost_map_2) do
    MapSet.new(Map.keys(cost_map_1) ++ Map.keys(cost_map_2))
    |> Enum.map(fn node ->
      cond do
        Map.has_key?(cost_map_1, node) and Map.has_key?(cost_map_2, node) ->
          cost_1 = cost_map_1[node]
          cost_2 = cost_map_2[node]
          {node, max(cost_1, cost_2)}

        Map.has_key?(cost_map_1, node) ->
          {node, cost_map_1[node]}

        true ->
          {node, cost_map_2[node]}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns the node with the lowest cost for a given cost map and alive set.
  """
  def min_alive_cost(cost_map, alive_set) do
    alive_costs = Enum.filter(cost_map, fn {node, _} -> MapSet.member?(alive_set, node) end)

    {min_node, _} =
      Enum.min(alive_costs, fn {node1, cost1}, {node2, cost2} ->
        cost1 < cost2 or (cost1 == cost2 and node1 < node2)
      end)

    min_node
  end

  # Represent state and orders in the format expected by the time_to_serve program.
  defp state_and_orders_to_external_format(
         {order_floor, order_btn_dir},
         elev_state,
         cab_orders,
         hall_orders
       ) do
    behavior_remap = [idle: "idle", moving: "moving", door_open: "doorOpen"][elev_state.behavior]
    order_dir_remap = [hall_up: :up, hall_down: :down][order_btn_dir]

    cab_orders_bool_table =
      0..(Elevator.num_floors() - 1)
      |> Enum.map(fn floor -> MapSet.member?(cab_orders, floor) end)

    hall_orders_bool_table =
      0..(Elevator.num_floors() - 1)
      |> Enum.map(fn floor ->
        [
          MapSet.member?(Map.get(hall_orders, floor, MapSet.new()), :hall_up),
          MapSet.member?(Map.get(hall_orders, floor, MapSet.new()), :hall_down)
        ]
      end)

    %{
      state: %{
        state: behavior_remap,
        floor: elev_state.floor,
        direction: elev_state.direction,
        cabRequests: cab_orders_bool_table
      },
      hallRequests: hall_orders_bool_table,
      newOrder: %{floor: order_floor, direction: order_dir_remap}
    }
  end
end
