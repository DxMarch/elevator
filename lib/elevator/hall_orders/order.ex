defmodule Elevator.HallOrders.Order do
  @moduledoc """
  Logic concerning a single Hall Order.

  A hall order is tied to a floor and direction (up/down). It is essentially
  one of the hall buttons. It is in one of the following states:
  - unknown: Initial, will transition to any state. Light: off
  - idle: No known order. Light: off
  - pending: Someone pressed a button, but everyone does not know it. Light: off
  - confirmed: All alive nodes know about the order and has indicated their preference to it. Light on.
  """

  alias Elevator.HallOrders.Scoring
  alias Elevator.Communicator

  @type hall_order_key :: Elevator.Types.hall_order_key()
  @type hall_order_value :: Elevator.Types.hall_order_value()

  @doc """
  Update a hall order based on an incoming hall order from another node.
  """
  @spec merge_hall_orders(hall_order_key(), hall_order_value(), hall_order_value()) ::
          hall_order_value()
  def merge_hall_orders(button_key, button_state, other_state) do
    new_button_state = merge_orders(button_key, button_state, other_state)
    # Ensure self is in any barrier set.
    case new_button_state do
      {:pending, barrier_set} ->
        {:pending, MapSet.put(barrier_set, Node.self())}

      {:confirmed, score_map, barrier_set} ->
        {:confirmed, score_map, MapSet.put(barrier_set, Node.self())}

      _ ->
        new_button_state
    end
  end

  @doc """
  Maybe update a hall order based on its own state.
  This may happen for example when the order autonomously transitions from pending to
  confirmed when only one elevator is alive.
  """
  @spec update_hall_order(hall_order_key(), hall_order_value()) :: {boolean(), hall_order_value()}
  def update_hall_order(key, button_state) do
    alive = Communicator.who_can_serve()

    case button_state do
      {:pending, ^alive} ->
        my_score = Scoring.compute_score(key)
        {true, {:confirmed, %{Node.self() => my_score}, MapSet.new([Node.self()])}}

      _ ->
        {false, button_state}
    end
  end

  defp merge_orders({floor, button_type}, my_state, other_state) do
    # This is the full state machine of the hall order consensus algorithm.
    case {my_state, other_state} do
      {:unknown, _} ->
        other_state

      {my_state, :unknown} ->
        my_state

      {:idle, {:confirmed, _, _}} ->
        :idle

      {:idle, _} ->
        other_state

      {{:confirmed, _, _}, :idle} ->
        :idle

      {_, :idle} ->
        my_state

      {{:pending, my_barrier}, {:pending, other_barrier}} ->
        {:pending, MapSet.union(my_barrier, other_barrier)}

      # {{:confirmed, score_map, my_barrier}, {:confirmed, score_map, other_barrier}} ->
      #   {:confirmed, score_map, MapSet.union(my_barrier, other_barrier)}

      # {{:confirmed, my_score_map, _}, {:confirmed, other_score_map, _}} ->
      #   {:confirmed, Scoring.merge_scores(my_score_map, other_score_map), MapSet.new()}

      {{:confirmed, my_score_map, my_barrier}, {:confirmed, other_score_map, other_barrier}} ->
        # Always union barriers, even when score maps differ, so the barrier
        # accumulates correctly as scores converge through exchanges.
        {:confirmed, Scoring.merge_scores(my_score_map, other_score_map),
         MapSet.union(my_barrier, other_barrier)}

      {{:confirmed, _, _}, _} ->
        my_state

      {{:pending, _}, {:confirmed, score_map, _}} ->
        my_score = Scoring.compute_score({floor, button_type})
        my_score_map = Map.put(score_map, Node.self(), my_score)
        {:confirmed, my_score_map, MapSet.new()}

      _ ->
        my_state
    end
  end
end
