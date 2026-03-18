defmodule Elevator.HallOrders.Order do
  @moduledoc """
  Logic concerning a single Hall Order.

  A hall order is tied to a floor and direction (up/down). It is essentially
  one of the hall buttons.
  The state of an order is one of the following:
  - idle: No known order. Light: off
  - pending: Someone pressed a button, but everyone does not know it. Light: off
  - confirmed: All alive nodes know about the order and has indicated their cost to serve it. Light on.
  - arrived: A node is signalling that the order has been served. Light: off
  """
  alias Elevator.HallOrders.Cost
  alias Elevator.Communicator

  @type floor :: Elevator.floor()
  @type hall_button :: Elevator.HallOrders.hall_button()
  @type hall_button_type :: Elevator.HallOrders.hall_button_type()
  @type hall_order_state :: Elevator.HallOrders.hall_order_state()

  @doc """
  Update a hall order based on an incoming hall order from another node.
  """
  @spec merge_hall_orders(hall_button(), hall_order_state(), hall_order_state(), %{
          floor() => MapSet.t(hall_button_type())
        }) ::
          hall_order_state()
  def merge_hall_orders(order_key, order_state, other_order_state, my_hall_orders) do
    new_order_state = merge_orders(order_state, other_order_state)

    # Ensure self is in any barrier set.
    new_order_state =
      case new_order_state do
        {:pending, barrier_set} ->
          {:pending, MapSet.put(barrier_set, Node.self())}

        {:arrived, barrier_set} ->
          {:arrived, MapSet.put(barrier_set, Node.self())}

        _ ->
          new_order_state
      end

    # Ensure self is in a cost map
    new_order_state =
      case new_order_state do
        {:handling, cost_map} ->
          my_id = Node.self()

          if not Map.has_key?(cost_map, my_id) do
            {:handling, Map.put(cost_map, my_id, Cost.compute_cost(order_key, my_hall_orders))}
          else
            new_order_state
          end

        _ ->
          new_order_state
      end

    new_order_state
  end

  @doc """
  Advances a pending order to confirmed if the barrier set is full.
  Computes and records this node's cost at the point of confirmation.
  Returns `{true, new_value}` if the state changed, `{false, unchanged}` otherwise.
  """
  @spec update_hall_order(hall_button(), hall_order_state(), %{
          floor() => MapSet.t(hall_button_type())
        }) :: {boolean(), hall_order_state()}
  def update_hall_order(order_key, order_state, confirmed_hall_orders) do
    alive = Communicator.who_is_alive()

    {did_change, new_state} =
      case order_state do
        {:pending, barrier_set} ->
          if MapSet.intersection(barrier_set, alive) == alive do
            my_cost = Cost.compute_cost(order_key, confirmed_hall_orders)
            {true, {:handling, %{Node.self() => my_cost}}}
          else
            {false, order_state}
          end

        {:arrived, barrier_set} ->
          if MapSet.intersection(barrier_set, alive) == alive do
            {true, :idle}
          else
            {false, order_state}
          end

        _ ->
          {false, order_state}
      end

    {did_change, new_state}
  end

  defp merge_orders(my_state, other_state) do
    case {my_state, other_state} do
      {:idle, {:arrived, _}} ->
        my_state

      {:idle, other_state} ->
        other_state

      {{:pending, _}, :idle} ->
        my_state

      {{:pending, my_barrier}, {:pending, other_barrier}} ->
        {:pending, MapSet.union(my_barrier, other_barrier)}

      {{:pending, _}, other_state} ->
        other_state

      {{:handling, my_cost_map}, {:handling, other_cost_map}} ->
        {:handling, Cost.merge_cost(my_cost_map, other_cost_map)}

      {{:handling, _}, {:arrived, _}} ->
        other_state

      {{:handling, _}, _} ->
        my_state

      {{:arrived, my_barrier}, {:arrived, other_barrier}} ->
        {:arrived, MapSet.union(my_barrier, other_barrier)}

      {{:arrived, _}, :idle} ->
        other_state

      _ ->
        my_state
    end
  end
end
