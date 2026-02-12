defmodule Elevator.HallOrders do
  @moduledoc """
  Module responsible for all changes occuring to the hall_order part of the state.
  """
  alias Elevator.HallOrders.Scoring
  alias Elevator.CabOrders
  alias Elevator.Communicator
  use GenServer

  @type state_t :: Elevator.State.hall_order_map()
  @type hall_order_t :: Elevator.State.Hall.t()

  def start_link(arg) do 
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec init(any()) :: {:ok, state_t()}
  def init(num_floors) do
    top_floor = num_floors - 1
    state = Range.new(0, top_floor)
    |> Enum.flat_map(fn floor -> 
      case floor do
        0 -> [{floor, :up}]
        ^top_floor -> [{floor, :down}]
        _ -> [{floor, :up}, {floor, :down}]
      end
    end)
    |> Enum.map(&{&1, :unknown})
    |> Enum.into(%{})
    {:ok, state}
  end

  @spec receive_state(state_t()) :: :ok
  def receive_state(other_state), do: GenServer.cast(__MODULE__, {:receive_state, other_state})

  @spec button_press(non_neg_integer(), :up | :down) :: :ok
  def button_press(floor, button_type), do: GenServer.cast(__MODULE__, {:button_press, floor, button_type})

  @spec arrived_at_floor(non_neg_integer(), :up | :down) :: :ok
  def arrived_at_floor(floor, button_type), do: GenServer.cast(__MODULE__, {:arrived_at_floor, floor, button_type})

  @doc """
  Fuse my state with incoming state for each button.
  """
  @spec handle_cast({:receive_state, state_t()}, state_t()) :: {:noreply, state_t(), {:continue, :update_state}}
  def handle_cast({:receive_state, other_state}, state) do
    new_state = Map.keys(state)
    |> Enum.map(fn key -> 
      new_value = merge_ensure_self_in_barrier(state, state[key], other_state[key])
      {key, new_value}
    end)
    |> Enum.into(%{})
    {:noreply, new_state, {:continue, :update_state}}
  end

  @spec handle_cast({:button_press, non_neg_integer(), :up | :down}, state_t()) :: {:noreply, state_t(), {:continue, :update_state}}
  def handle_cast({:button_press, floor, direction}, order_map) do
    # If in idle or unknown, go to pending. Otherwise, ignore.
    key = {floor, direction}
    order_state = order_map[key]
    order_map = case order_state do
      :unknown ->
        Map.put(order_map, key, {:pending, MapSet.new([Node.self()])})
      :idle ->
        Map.put(order_map, key, {:pending, MapSet.new([Node.self()])})
      _ ->
        order_map
    end
    {:noreply, order_map, {:continue, :update_state}}
  end

  def handle_cast({:arrived_at_floor, floor, direction}, order_map) do
    # If in confirmed or unknown, go to idle. Otherwise, ignore.
    # TODO: Find out if barrier set should be full as well?
    key = {floor, direction}
    order_state = order_map[key]
    order_map = case order_state do
      :unknown ->
        Map.put(order_map, key, :idle)
      {:confirmed, _, _} ->
        Map.put(order_map, key, :idle)
      _ ->
        order_map
    end
    # For now, idle should not cause any further changes. So no continue here.
    {:noreply, order_map}
  end

  @doc """
  May advance some states, in which case continue is called until convergence.
  """
  @spec handle_continue(:update_state, state_t()) :: {:noreply, state_t()} | {:noreply, state_t(), {:continue, :update_state}}
  def handle_continue(:update_state, state) do
    {any_did_change, new_state} = Enum.reduce(state, {false, %{}}, 
      fn {key, button_state}, {acc_did_change, acc_state} ->
        {did_change, new_button_state} = update_button_state(state, button_state)
        {acc_did_change or did_change, Map.put(acc_state, key, new_button_state)}
      end)
    if any_did_change do
      {:noreply, new_state, {:continue, :update_state}}
    else
      {:noreply, state}
    end
  end

  defp merge_ensure_self_in_barrier(full_state, button_state, other_state) do
    new_button_state = merge_button_states(full_state, button_state, other_state)
    case new_button_state do
      {:pending, barrier_set} ->
        {:pending, MapSet.put(barrier_set, Node.self())}
      {:confirmed, score_map, barrier_set} ->
        {:confirmed, score_map, MapSet.put(barrier_set, Node.self())}
      _ -> new_button_state
    end
  end

  # Unknown goes to any state
  defp merge_button_states(_full_state, :unknown, other_state) do
    other_state
  end

  defp merge_button_states(_full_state, my_state, :unknown) do
    my_state
  end

  # Idle cannot go to confirmed
  defp merge_button_states(_full_state, :idle, {:confirmed, _, _}) do
    :idle
  end

  # Idle jumps to pending
  defp merge_button_states(_full_state, :idle, {:pending, barrier}) do
    {:pending, barrier}
  end

  # Pending unions with other pending
  defp merge_button_states(_full_state, {:pending, my_barrier}, {:pending, other_barrier}) do
    {:pending, MapSet.union(my_barrier, other_barrier)}
  end

  # Pending jumps to confirmed and computes score
  defp merge_button_states(
    full_state, 
    {:pending, _}, 
    {:confirmed, other_score_map, other_barrier}
  ) do
    cab_orders = CabOrders.get_orders()
    my_score = Elevator.HallOrders.Scoring.compute_score(full_state, cab_orders)
    my_score_map = Map.put(other_score_map, Node.self(), my_score)

    if my_score_map == other_score_map do
      {:confirmed, my_score_map, other_barrier}
    else
      {:confirmed, my_score_map, MapSet.new()}
    end
  end

  defp merge_button_states(
    _full_state,
    {:confirmed, my_score_map, my_barrier},
    {:confirmed, other_score_map, other_barrier}
  ) do
    cond do
      my_score_map == other_score_map ->
        {:confirmed, my_score_map, MapSet.union(my_barrier, other_barrier)}
      true ->
        {:confirmed, Scoring.merge_scores(my_score_map, other_score_map), MapSet.new()}
    end
  end

  @spec update_button_state(state_t(), hall_order_t()) :: {boolean(), hall_order_t()}
  defp update_button_state(full_state, button_state) do
    alive = Communicator.who_is_alive()
    # TODO: Logic when confirmed barrier gets full?
    case button_state do
      {:pending, ^alive} ->
        cab_orders = CabOrders.get_orders()
        my_score = Elevator.HallOrders.Scoring.compute_score(full_state, cab_orders)
        {true, {:confirmed, %{Node.self() => my_score}, MapSet.new([Node.self()])}}
      _ ->
        {false, button_state}
    end
  end
end
