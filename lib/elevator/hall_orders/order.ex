defmodule Elevator.HallOrders.Order do
  @moduledoc """
  Logic concerning a single Hall Order.

  A hall order is tied to a floor and direction (up/down). 
  It is essentially one of the hall buttons.
  The state of an order is one of the following:
  - idle: No known order. Light: off
  - pending: Someone pressed a button, but everyone does not know it. Light: off
  - handling: All alive nodes know about the order and has indicated their cost to serve it. Light: on.
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
  @spec update_from_incoming(
          hall_button(),
          hall_order_state(),
          hall_order_state(),
          %{floor() => MapSet.t(hall_button_type())}
        ) :: hall_order_state()
  def update_from_incoming(order_key, order_state, incoming_order_state, my_hall_orders) do
    order_state
    |> merge_with_incoming(incoming_order_state)
    |> ensure_self_in_barriers()
    |> ensure_self_in_cost_map(order_key, my_hall_orders)
  end

  @doc """
  Advances a pending or arrived order if the respective barrier set is full.
  Returns `{true, new_value}` if the state changed, `{false, old_value}` otherwise.
  """
  @spec update_from_barrier_state(
          hall_button(),
          hall_order_state(),
          %{floor() => MapSet.t(hall_button_type())}
        ) :: hall_order_state()
  def update_from_barrier_state(order_key, order_state, my_hall_orders) do
    order_state
    |> transition_from_barrier_state(Communicator.who_is_alive())
    |> ensure_self_in_barriers()
    |> ensure_self_in_cost_map(order_key, my_hall_orders)
  end

  @spec update_from_button_press(hall_order_state()) :: hall_order_state()
  def update_from_button_press(:idle) do
    ensure_self_in_barriers({:pending, MapSet.new()})
  end

  def update_from_button_press(order_state), do: order_state

  @spec update_from_button_press(hall_order_state()) :: hall_order_state()
  def update_from_arrived_at_floor({:handling, _}) do
    ensure_self_in_barriers({:arrived, MapSet.new()})
  end

  def update_from_arrived_at_floor(order_state), do: order_state

  # Helpers --------------------------------------------------

  # Cyclic counter logic for updating a state when receiving from another node.
  defp merge_with_incoming(my_state, incoming_state) do
    case {my_state, incoming_state} do
      {:idle, {:arrived, _}} ->
        my_state

      {:idle, incoming_state} ->
        incoming_state

      {{:pending, _}, :idle} ->
        my_state

      {{:pending, my_barrier}, {:pending, incoming_barrier}} ->
        {:pending, MapSet.union(my_barrier, incoming_barrier)}

      {{:pending, _}, incoming_state} ->
        incoming_state

      {{:handling, my_cost_map}, {:handling, incoming_cost_map}} ->
        {:handling, Cost.merge_cost(my_cost_map, incoming_cost_map)}

      {{:handling, _}, {:arrived, _}} ->
        incoming_state

      {{:handling, _}, _} ->
        my_state

      {{:arrived, my_barrier}, {:arrived, incoming_barrier}} ->
        {:arrived, MapSet.union(my_barrier, incoming_barrier)}

      {{:arrived, _}, :idle} ->
        incoming_state

      _ ->
        my_state
    end
  end

  defp transition_from_barrier_state(order_state = {:pending, barrier_set}, alive) do
    if MapSet.subset?(alive, barrier_set),
      do: {:handling, %{}},
      else: order_state
  end

  defp transition_from_barrier_state(order_state = {:arrived, barrier_set}, alive) do
    if MapSet.subset?(alive, barrier_set),
      do: :idle,
      else: order_state
  end

  defp transition_from_barrier_state(order_state, _), do: order_state

  defp ensure_self_in_barriers({state, barrier_set}) when state in [:pending, :arrived] do
    {state, MapSet.put(barrier_set, Node.self())}
  end

  defp ensure_self_in_barriers(order_state), do: order_state

  defp ensure_self_in_cost_map({:handling, cost_map}, order_key, my_hall_orders) do
    {:handling,
     Map.put_new_lazy(cost_map, Node.self(), fn ->
       Cost.compute_cost(order_key, my_hall_orders)
     end)}
  end

  defp ensure_self_in_cost_map(order_state, _, _), do: order_state
end
