defmodule Elevator.HallOrders.Cost do
  @moduledoc """
  Hall order cost utilities.

  Cost is estimated by simulating the local elevator with current requests plus the candidate hall request.
  """

  alias Elevator.CabOrders
  alias Elevator.Decision
  alias Elevator.FSM.State
  require Logger

  @travel_duration_ms 2500
  @max_simulation_steps 256
  @unreachable_cost 30000

  @type floor :: Elevator.Types.floor()
  @type hall_btn :: Elevator.Types.hall_btn()
  @type combined_order_map :: Elevator.Types.combined_order_map()
  @type cost_map :: Elevator.Types.hall_order_cost_map()

  @spec compute_cost({floor(), hall_btn()}, %{floor() => MapSet.t(hall_btn())}) ::
          non_neg_integer()
  def compute_cost({floor, btn_dir}, my_hall_orders) do
    try do
      state = State.get_state()
      cab_orders = CabOrders.get_my_orders()

      hall_orders_with_target =
        Map.update(my_hall_orders, floor, MapSet.new([btn_dir]), &MapSet.put(&1, btn_dir))

      combined_orders = Decision.combine_hall_and_cab(hall_orders_with_target, cab_orders)

      result = simulate_cost_until_served(combined_orders, state, {floor, btn_dir})

      Logger.debug(fn ->
        "hall_cost request=#{inspect({floor, btn_dir})} state=#{state.behavior}@#{inspect(state.floor)} dir=#{state.direction} result=#{result}"
      end)

      result
    rescue
      error ->
        Logger.warning(
          "Failed to compute hall cost for #{inspect({floor, btn_dir})}: #{inspect(error)}"
        )

        @unreachable_cost
    end
  end

  @doc """
  Merge two cost maps.
  Uses pessimistic merge: If two conflicting costs for the same node are found, keep the higher one.
  """
  @spec merge_cost(cost_map(), cost_map()) :: cost_map()
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

  @spec simulate_cost_until_served(combined_order_map(), State.t(), {floor(), hall_btn()}) ::
          non_neg_integer()
  defp simulate_cost_until_served(_orders, %{floor: :unknown}, _target), do: @unreachable_cost

  defp simulate_cost_until_served(_orders, %{obstructed: true}, _target),
    do: @unreachable_cost

  defp simulate_cost_until_served(orders, state, target) do
    normalized_state =
      if state.direction in [:up, :down], do: state, else: %{state | direction: :down}

    initial_time_ms =
      if normalized_state.behavior == :door_open and elem(target, 0) != normalized_state.floor do
        Elevator.door_open_duration_ms()
      else
        0
      end

    if target_cleared?(orders, target) do
      0
    else
      do_simulate(orders, normalized_state, target, initial_time_ms, @max_simulation_steps)
    end
  end

  defp do_simulate(_orders, _state, _target, _time_ms, 0), do: @unreachable_cost

  defp do_simulate(orders, state, target, time_ms, steps_left) do
    if target_cleared?(orders, target) do
      time_ms
    else
      {direction, behavior} = Decision.next_action(orders, state)

      case behavior do
        :idle ->
          @unreachable_cost

        :moving ->
          case move_one_floor(state.floor, direction) do
            {:ok, next_floor} ->
              next_state = %{
                state
                | floor: next_floor,
                  between_floors: false,
                  direction: direction,
                  behavior: :moving
              }

              do_simulate(
                orders,
                next_state,
                target,
                time_ms + @travel_duration_ms,
                steps_left - 1
              )

            :error ->
              @unreachable_cost
          end

        :door_open ->
          next_orders = clear_requests_at_floor_in_direction(orders, state.floor, direction)

          next_state = %{
            state
            | direction: direction,
              behavior: :idle,
              between_floors: false
          }

          do_simulate(
            next_orders,
            next_state,
            target,
            time_ms + Elevator.door_open_duration_ms(),
            steps_left - 1
          )
      end
    end
  end

  defp target_cleared?(orders, {floor, btn_dir}) do
    orders
    |> Map.get(floor, MapSet.new())
    |> MapSet.member?(btn_dir)
    |> Kernel.not()
  end

  defp move_one_floor(floor, :up) when is_integer(floor) do
    if floor < Elevator.num_floors() - 1, do: {:ok, floor + 1}, else: :error
  end

  defp move_one_floor(floor, :down) when is_integer(floor) do
    if floor > 0, do: {:ok, floor - 1}, else: :error
  end

  defp move_one_floor(_, _), do: :error

  defp clear_requests_at_floor_in_direction(orders, floor, direction) do
    orders
    |> clear_button(floor, :cab)
    |> clear_hall_for_direction(floor, direction)
    |> prune_empty_floor(floor)
  end

  defp clear_hall_for_direction(orders, floor, :up) do
    cond do
      button_present?(orders, floor, :hall_up) ->
        clear_button(orders, floor, :hall_up)

      Decision.requests_above?(orders, floor) ->
        orders

      true ->
        # No reason to continue up: clear hall down when turning around
        clear_button(orders, floor, :hall_down)
    end
  end

  defp clear_hall_for_direction(orders, floor, :down) do
    cond do
      button_present?(orders, floor, :hall_down) ->
        clear_button(orders, floor, :hall_down)

      Decision.requests_below?(orders, floor) ->
        orders

      true ->
        clear_button(orders, floor, :hall_up)
    end
  end

  defp button_present?(orders, floor, btn) do
    orders
    |> Map.get(floor, MapSet.new())
    |> MapSet.member?(btn)
  end

  defp clear_button(orders, floor, btn) do
    case Map.get(orders, floor) do
      nil ->
        orders

      buttons ->
        Map.put(orders, floor, MapSet.delete(buttons, btn))
    end
  end

  defp prune_empty_floor(orders, floor) do
    case Map.get(orders, floor) do
      nil ->
        orders

      buttons ->
        if MapSet.size(buttons) == 0 do
          Map.delete(orders, floor)
        else
          orders
        end
    end
  end
end
