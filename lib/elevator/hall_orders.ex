defmodule Elevator.HallOrders do
  @moduledoc """
  Module responsible for all changes occuring to the hall_order part of the state.
  """
  alias Elevator.HallOrders.Scoring
  alias Elevator.CabOrders
  alias Elevator.Communicator
  use GenServer

  @type state_t :: Elevator.Types.hall_order_map()
  @type hall_order_t :: Elevator.Types.hall_order_value()

  def start_link(arg) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec init(any()) :: {:ok, state_t()}
  def init(num_floors) do
    top_floor = num_floors - 1
    state = Range.new(0, top_floor)
    |> Enum.flat_map(fn floor ->
      case floor do
        0 -> [{floor, :hall_up}]
        ^top_floor -> [{floor, :hall_down}]
        _ -> [{floor, :hall_up}, {floor, :hall_down}]
      end
    end)
    |> Enum.map(&{&1, :unknown})
    |> Enum.into(%{})
    {:ok, state}
  end

  @doc """
  Callback for receiving the hall order state from another node.
  Merges the states by updating the individual
  """
  @spec receive_state(state_t()) :: :ok
  def receive_state(other_state), do: GenServer.cast(__MODULE__, {:receive_state, other_state})

  @doc """
  Callback for a button press.
  """
  @spec button_press(non_neg_integer(), :hall_up | :hall_down) :: :ok
  def button_press(floor, button_type), do: GenServer.cast(__MODULE__, {:button_press, floor, button_type})

  @doc """
  Callback for clearing a floor.
  """
  @spec arrived_at_floor(non_neg_integer(), :up | :down) :: :ok
  def arrived_at_floor(floor, direction) do
    GenServer.cast(__MODULE__, {:arrived_at_floor, floor, direction})
  end

  @spec get_my_orders() :: %{Elevator.Types.floor() => MapSet.t(Elevator.Types.hall_btn())}
  def get_my_orders do
    GenServer.call(__MODULE__, :get_my_orders)
  end

  @doc """
  Retrieve the full hall order state map
  """
  @spec get_state() :: state_t()
  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  def handle_call(:get_my_orders, _from, order_map) do
    alive = Communicator.who_is_alive()
    my_orders = Enum.filter(order_map, fn {_, order_state} ->
      case order_state do
        {:confirmed, score_map, barrier_set} ->
          # Hmm.
          if MapSet.intersection(barrier_set, alive) != alive do
            false
          else
            Scoring.max_alive_score(score_map, alive) == Node.self()
          end
        _ -> false
      end
    end)
    |> Enum.map(fn {{floor, btn_type}, _} ->
      {floor, btn_type}
    end)
    |> Enum.group_by(fn {floor, _} -> floor end)
    |> Enum.map(fn {floor, order_list} ->
      {floor, MapSet.new(Enum.map(order_list, fn {_, btn_type} -> btn_type end))}
    end)
    |> Enum.into(%{})
    {:reply, my_orders, order_map}
  end

  def handle_call(:get_state, _, order_map) do
    {:reply, order_map, order_map}
  end

  @spec handle_cast({:receive_state, state_t()}, state_t()) :: {:noreply, state_t(), {:continue, :hall_update_state}}
  def handle_cast({:receive_state, other_order_map}, order_map) do
    new_order_map = Map.keys(order_map)
    |> Enum.map(fn key ->
      new_value = merge_ensure_self_in_barrier(order_map, order_map[key], other_order_map[key])
      {key, new_value}
    end)
    |> Enum.into(%{})
    {:noreply, new_order_map, {:continue, :hall_update_state}}
  end

  @spec handle_cast({:button_press, non_neg_integer(), :hall_up | :hall_down}, state_t()) :: {:noreply, state_t(), {:continue, :hall_update_state}}
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
    {:noreply, order_map, {:continue, :hall_update_state}}
  end

  def handle_cast({:arrived_at_floor, floor, direction}, order_map) do
    # If in confirmed or unknown, go to idle. Otherwise, ignore.
    # TODO: Find out if barrier set should be full as well?
    button_type = [up: :hall_up, down: :hall_down][direction]
    key = {floor, button_type}
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
  @spec handle_continue(:hall_update_state, state_t()) :: {:noreply, state_t()} | {:noreply, state_t(), {:continue, :hall_update_state}}
  def handle_continue(:hall_update_state, order_map) do
    {any_did_change, new_order_map} = Enum.reduce(order_map, {false, %{}},
      fn {key, button_state}, {acc_did_change, acc_order_map} ->
        {did_change, new_button_state} = update_button_state(order_map, button_state)
        {acc_did_change or did_change, Map.put(acc_order_map, key, new_button_state)}
      end)
    if any_did_change do
      {:noreply, new_order_map, {:continue, :hall_update_state}}
    else
      {:noreply, new_order_map}
    end
  end

  # Wrapper for merge_button_states that ensures Node.self() is in the barrier state.
  defp merge_ensure_self_in_barrier(order_map, button_state, other_state) do
    # pending -> confirmed -> give order_map as well
    new_button_state = case {button_state, other_state} do
      {{:pending, _}, {:confirmed, _, _}} ->
        merge_button_states(button_state, other_state, order_map)
      _ ->
        merge_button_states(button_state, other_state)
    end
    case new_button_state do
      {:pending, barrier_set} ->
        {:pending, MapSet.put(barrier_set, Node.self())}
      {:confirmed, score_map, barrier_set} ->
        {:confirmed, score_map, MapSet.put(barrier_set, Node.self())}
      _ -> new_button_state
    end
  end

  # Unknown goes to any state
  defp merge_button_states(:unknown, other_state) do
    other_state
  end

  defp merge_button_states(my_state, :unknown) do
    my_state
  end

  # Idle jumps to pending
  defp merge_button_states(:idle, {:pending, barrier}) do
    {:pending, barrier}
  end

  # Pending unions with other pending
  defp merge_button_states({:pending, my_barrier}, {:pending, other_barrier}) do
    {:pending, MapSet.union(my_barrier, other_barrier)}
  end

  # Idle cannot go to confirmed
  defp merge_button_states(:idle, {:confirmed, _, _}) do
    :idle
  end

  # Otherwise idle goes to anything
  defp merge_button_states(:idle, other) do
    other
  end

  # But confirmed goes to idle
  defp merge_button_states({:confirmed, _, _}, :idle) do
    # TODO: find out if barrier set must be full
    :idle
  end

  defp merge_button_states(
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

  # Pending jumps to confirmed and computes score
  defp merge_button_states(
    {:pending, _},
    {:confirmed, other_score_map, other_barrier},
    order_map
  ) do
    cab_orders = CabOrders.get_my_orders()
    my_score = Elevator.HallOrders.Scoring.compute_score(order_map, cab_orders)
    my_score_map = Map.put(other_score_map, Node.self(), my_score)

    if my_score_map == other_score_map do
      {:confirmed, my_score_map, other_barrier}
    else
      {:confirmed, my_score_map, MapSet.new()}
    end
  end

  @spec update_button_state(state_t(), hall_order_t()) :: {boolean(), hall_order_t()}
  defp update_button_state(order_map, button_state) do
    alive = Communicator.who_is_alive()
    # TODO: Logic when confirmed barrier gets full?
    case button_state do
      {:pending, ^alive} ->
        cab_orders = CabOrders.get_my_orders()
        my_score = Elevator.HallOrders.Scoring.compute_score(order_map, cab_orders)
        {true, {:confirmed, %{Node.self() => my_score}, MapSet.new([Node.self()])}}
      _ ->
        {false, button_state}
    end
  end
end
