defmodule Elevator.HallOrders.Order do
  @moduledoc """
  Logic concerning a single Hall Order.

  A hall order is tied to a floor and direction (up/down). It is essentially
  one of the hall buttons. It is in one of the following states:
  - idle: No known order. Light: off
  - pending: Someone pressed a button, but everyone does not know it. Light: off
  - confirmed: All alive nodes know about the order and has indicated their preference to it. Light on.
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
  def merge_hall_orders(button_key, button_state, other_state, my_hall_orders) do
    {new_button_version, new_button_state} = merge_orders(button_state, other_state)
    # Ensure self is in any barrier set.
    {new_button_version, new_button_state} =
      case new_button_state do
        {:pending, barrier_set} ->
          {new_button_version, {:pending, MapSet.put(barrier_set, Node.self())}}

        _ ->
          {new_button_version, new_button_state}
      end

    # Ensure self is in a score map
    case new_button_state do
      {:confirmed, cost_map} ->
        my_id = Communicator.my_id()

        if not Map.has_key?(cost_map, my_id) do
          {new_button_version,
           {:confirmed, Map.put(cost_map, my_id, Cost.compute_cost(button_key, my_hall_orders))}}
        else
          {new_button_version, new_button_state}
        end

      _ ->
        {new_button_version, new_button_state}
    end
  end

  @doc """
  Advances a pending order to confirmed if the barrier set is full.
  Computes and records this node's cost at the point of confirmation.
  Returns `{true, new_value}` if the state changed, `{false, unchanged}` otherwise.
  """
  @spec update_hall_order(hall_order_key(), hall_order_value(), %{
          Types.floor() => MapSet.t(Types.hall_btn())
        }) :: {boolean(), hall_order_value()}
  def update_hall_order(key, {button_version, button_state}, confirmed_hall_orders) do
    alive = Communicator.who_can_serve()

    case button_state do
      {:pending, barrier_set} ->
        if MapSet.intersection(barrier_set, alive) == alive do
          my_cost = Cost.compute_cost(key, confirmed_hall_orders)
          {true, {button_version, {:confirmed, %{Communicator.my_id() => my_cost}}}}
        else
          {false, {button_version, button_state}}
        end

      _ ->
        {false, {button_version, button_state}}
    end
  end

  defp merge_orders({my_version, my_state}, {other_version, other_state}) do
    # This is the full state machine of the hall order consensus algorithm.
    cond do
      my_version > other_version ->
        {my_version, my_state}

      my_version < other_version ->
        {other_version, other_state}

      true ->
        case {my_state, other_state} do
          {:idle, other_state} ->
            {other_version, other_state}

          {_, :idle} ->
            {my_version, my_state}

          {{:pending, my_barrier}, {:pending, other_barrier}} ->
            {my_version, {:pending, MapSet.union(my_barrier, other_barrier)}}

          {{:confirmed, my_cost_map}, {:confirmed, other_cost_map}} ->
            {my_version, {:confirmed, Cost.merge_cost(my_cost_map, other_cost_map)}}

          {{:confirmed, _}, _} ->
            {my_version, my_state}

          {_, {:confirmed, _}} ->
            {other_version, other_state}

          _ ->
            {my_version, my_state}
        end
    end
  end
end
