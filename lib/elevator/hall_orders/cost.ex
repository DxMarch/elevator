defmodule Elevator.HallOrders.Cost do
  @moduledoc """
  Hall order cost utilities.

  Cost is estimated by simulating the local elevator with current requests plus the candidate hall request.
  """

  alias Elevator.CabOrders
  alias Elevator.Decision
  alias Elevator.FSM.State
  alias Elevator.HallOrders.Simulation
  require Logger

  @type floor :: Elevator.floor()
  @type hall_button_type :: Elevator.HallOrders.hall_button_type()
  @type cost_map :: Elevator.HallOrders.hall_order_cost_map()

  @spec compute_cost({floor(), hall_button_type()}, %{floor() => MapSet.t(hall_button_type())}) ::
          non_neg_integer()
  def compute_cost({floor, hall_button_type}, my_hall_orders) do
    state = State.get_state()
    cab_orders = CabOrders.get_my_orders()

    hall_orders_with_target =
      Map.update(
        my_hall_orders,
        floor,
        MapSet.new([hall_button_type]),
        &MapSet.put(&1, hall_button_type)
      )

    combined_orders = Decision.combine_hall_and_cab(hall_orders_with_target, cab_orders)

    result =
      Simulation.simulate_time_until_served(combined_orders, state, {floor, hall_button_type})

    Logger.debug(fn ->
      "hall_cost request=#{inspect({floor, hall_button_type})} state=#{state.behavior}@#{inspect(state.floor)} dir=#{state.direction} result=#{result}"
    end)

    result
  end

  @doc """
  Merge two cost maps.
  Uses pessimistic merge: If two conflicting costs for the same node are found, keep the higher one.
  """
  @spec merge_cost(cost_map(), cost_map()) :: cost_map()
  def merge_cost(cost_map, other_cost_map) do
    MapSet.new(Map.keys(cost_map) ++ Map.keys(other_cost_map))
    |> Enum.map(fn node ->
      cond do
        Map.has_key?(cost_map, node) and Map.has_key?(other_cost_map, node) ->
          cost = cost_map[node]
          other_cost = other_cost_map[node]
          {node, max(cost, other_cost)}

        Map.has_key?(cost_map, node) ->
          {node, cost_map[node]}

        true ->
          {node, other_cost_map[node]}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Returns the node with the lowest cost for a given cost map and alive set.
  """
  @spec min_alive_cost(cost_map(), MapSet.t(node())) :: node()
  def min_alive_cost(cost_map, alive_set) do
    alive_costs = Enum.filter(cost_map, fn {node, _} -> MapSet.member?(alive_set, node) end)

    if Enum.count(alive_costs) != MapSet.size(alive_set) do
      nil
    else
      {min_node, _} =
        Enum.min(
          alive_costs,
          fn {node1, cost1}, {node2, cost2} ->
            cost1 < cost2 or (cost1 == cost2 and node1 < node2)
          end,
          # Fallback when no alive costs exist
          fn -> {:nonode@nohost, :infinity} end
        )

      min_node
    end
  end
end
