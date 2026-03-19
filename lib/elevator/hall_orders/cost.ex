defmodule Elevator.HallOrders.Cost do
  @moduledoc """
  Hall order cost utilities.

  Cost is estimated by simulating the local elevator with current orders plus the candidate hall order.
  See `m:Elevator.HallOrders.Simulation` for simulation logic.
  """

  alias Elevator.HallOrders
  alias Elevator.CabOrders
  alias Elevator.FSM.State
  alias Elevator.OrderUtils
  alias Elevator.HallOrders.Simulation
  require Logger

  @doc """
  Compute the cost (time to serve) of a candidate hall order by simulating single elevator logic.
  """
  @spec compute_cost(
          {Elevator.floor(), Elevator.HallOrders.hall_button_type()},
          %{Elevator.floor() => MapSet.t(Elevator.HallOrders.hall_button_type())}
        ) ::
          non_neg_integer()
  def compute_cost({floor, hall_button_type}, my_hall_orders) do
    state = State.get_state()
    cab_orders = CabOrders.get_my_orders()

    # Include the candidate hall order in our local hall-order snapshot before simulating.
    hall_orders_with_candidate =
      Map.update(
        my_hall_orders,
        floor,
        MapSet.new([hall_button_type]),
        &MapSet.put(&1, hall_button_type)
      )

    combined_orders = OrderUtils.combine_hall_and_cab(hall_orders_with_candidate, cab_orders)

    Simulation.simulate_time_until_served(combined_orders, state, {floor, hall_button_type})
  end

  @doc """
  Merge two cost maps.
  Uses pessimistic merge: If two conflicting costs for the same node are found, keep the higher one.
  """
  @spec merge_cost(HallOrders.cost_map(), HallOrders.cost_map()) :: HallOrders.cost_map()
  def merge_cost(cost_map, other_cost_map) do
    Map.merge(cost_map, other_cost_map, fn _node, cost, other_cost ->
      max(cost, other_cost)
    end)
  end

  @doc """
  Returns if we are supposed to take the order given the cost map.
  Assumes who_can_serve is a subset of cost_map keys.
  """
  @spec assigned_to_me?(HallOrders.cost_map(), MapSet.t(node())) :: boolean()
  def assigned_to_me?(cost_map, who_can_serve) do
    {min_node, _} =
      Enum.filter(cost_map, fn {node, _} -> MapSet.member?(who_can_serve, node) end)
      |> Enum.min_by(fn {node, cost} -> {cost, node} end, fn -> {:infinity, :nonode@nohost} end)

    min_node == Node.self()
  end
end
