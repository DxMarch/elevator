defmodule Elevator.HallOrders.Order do
  @moduledoc """
  Logic concerning a single Hall Order.

  A hall order is tied to a floor and direction (up/down). It is essentially
  one of the hall buttons. An order has both a version number and a state.
  State is one of the following:
  - idle: No known order. Light: off
  - pending: Someone pressed a button, but everyone does not know it. Light: off
  - confirmed: All alive nodes know about the order and has indicated their cost to serve it. Light on.
  """

  alias Elevator.Types
  alias Elevator.HallOrders.Cost
  alias Elevator.Communicator

  @type hall_order_key :: Elevator.Types.hall_order_key()
  @type hall_order_value :: Elevator.Types.hall_order_value()

  @doc """
  Update a hall order based on an incoming hall order from another node.
  """
  @spec merge_hall_orders(hall_order_key(), hall_order_value(), hall_order_value(), %{
          Types.floor() => MapSet.t(Types.hall_btn())
        }) ::
          hall_order_value()
  def merge_hall_orders(order_key, order_value, other_order_value, my_hall_orders) do
    {new_order_version, new_order_state} = merge_orders(order_value, other_order_value)

    # Ensure self is in any barrier set.
    new_order_state =
      case new_order_state do
        {:pending, barrier_set} ->
          {:pending, MapSet.put(barrier_set, Node.self())}

        _ ->
          new_order_state
      end

    # Ensure self is in a score map
    new_order_state =
      case new_order_state do
        {:confirmed, cost_map} ->
          my_id = Communicator.my_id()

          if not Map.has_key?(cost_map, my_id) do
            {:confirmed, Map.put(cost_map, my_id, Cost.compute_cost(order_key, my_hall_orders))}
          else
            new_order_state
          end

        _ ->
          new_order_state
      end

    {new_order_version, new_order_state}
  end

  @doc """
  Advances a pending order to confirmed if the barrier set is full.
  Computes and records this node's cost at the point of confirmation.
  Returns `{true, new_value}` if the state changed, `{false, unchanged}` otherwise.
  """
  @spec update_hall_order(hall_order_key(), hall_order_value(), %{
          Types.floor() => MapSet.t(Types.hall_btn())
        }) :: {boolean(), hall_order_value()}
  def update_hall_order(order_key, {order_version, order_state}, confirmed_hall_orders) do
    alive = Communicator.who_can_serve()

    {did_change, new_state} =
      case order_state do
        {:pending, barrier_set} ->
          if MapSet.intersection(barrier_set, alive) == alive do
            my_cost = Cost.compute_cost(order_key, confirmed_hall_orders)
            {true, {:confirmed, %{Communicator.my_id() => my_cost}}}
          else
            {false, order_state}
          end

        _ ->
          {false, order_state}
      end

    {did_change, {order_version, new_state}}
  end

  defp merge_orders({my_version, my_state}, {other_version, other_state}) do
    cond do
      my_version > other_version ->
        {my_version, my_state}

      my_version < other_version ->
        {other_version, other_state}

      true ->
        case {my_state, other_state} do
          {{:pending, my_barrier}, {:pending, other_barrier}} ->
            {my_version, {:pending, MapSet.union(my_barrier, other_barrier)}}

          {{:confirmed, my_cost_map}, {:confirmed, other_cost_map}} ->
            {my_version, {:confirmed, Cost.merge_cost(my_cost_map, other_cost_map)}}

          {:idle, _} ->
            {other_version, other_state}

          {_, {:confirmed, _}} ->
            {other_version, other_state}

          _ ->
            {my_version, my_state}
        end
    end
  end
end
