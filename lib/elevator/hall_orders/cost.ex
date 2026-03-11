defmodule Elevator.HallOrders.Cost do
  alias Elevator.CabOrders
  require Logger

  @doc """
  Maybe even random numbers?
  """
  def compute_cost({floor, btn_dir}, my_hall_orders) do
    state = Elevator.FSM.State.get_state()

    # Represent state and orders in the format expected by time_to_serve
    cab_orders = CabOrders.get_my_orders()
    behavior_str = [idle: "idle", moving: "moving", door_open: "doorOpen"][state.behavior]

    elev_state = %{
      state: %{
        state: behavior_str,
        floor: state.floor,
        direction: state.direction,
        cabRequests:
          Enum.map(0..(Elevator.num_floors() - 1), fn floor ->
            MapSet.member?(cab_orders, floor)
          end)
      },
      hallRequests:
        Enum.map(
          0..(Elevator.num_floors() - 1),
          fn floor ->
            [
              MapSet.member?(Map.get(my_hall_orders, floor, MapSet.new()), :hall_up),
              MapSet.member?(Map.get(my_hall_orders, floor, MapSet.new()), :hall_down)
            ]
          end
        ),
      newOrder: %{floor: floor, direction: [hall_up: :up, hall_down: :down][btn_dir]}
    }

    json_input = JSON.encode!(elev_state)

    try do
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
end
