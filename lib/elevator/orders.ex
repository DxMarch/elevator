defmodule Elevator.Orders do
  @moduledoc """
  Pure functions for elevator request manipulation.

  These functions are intentionally pure to make them easy to unit test.
  """

  # Private helpers

  defp requests_above?(reqs, floor) do
    Enum.any?(reqs, fn {f, _} -> f > floor end)
  end

  defp requests_below?(reqs, floor) do
    Enum.any?(reqs, fn {f, _} -> f < floor end)
  end

  defp request_here?(reqs, floor) do
    Enum.any?(reqs, fn {f, _} -> f == floor end)
  end

  # @doc "Should a request at `btn_floor` and `btn_type` be cleared immediately given elevator state?"
  # @spec should_clear_immediately?(
  #         Elevator.State.t(),
  #         Elevator.Types.floor(),
  #         Elevator.Types.btn_type()
  #       ) :: boolean()
  # def should_clear_immediately?(
  #       %Elevator.State{floor: floor, direction: direction},
  #       btn_floor,
  #       btn_type
  #     )
  #     when floor == btn_floor do
  #   cond do
  #     btn_type == :cab -> true
  #     direction == :up and btn_type == :hall_up -> true
  #     direction == :down and btn_type == :hall_down -> true
  #     direction == :stop -> true
  #     true -> false
  #   end
  # end

  # def should_clear_immediately?(_, _, _), do: false

  @spec combine_new_cab_orders(
          Elevator.Types.combined_order_map(),
          MapSet.t(Elevator.Types.floor())
        ) :: Elevator.Types.combined_order_map()
  def combine_new_cab_orders(old_orders, new_cab_orders) do
    Enum.reduce(new_cab_orders, old_orders, fn floor, acc ->
      Map.update(acc, floor, MapSet.new([:cab]), &MapSet.put(&1, :cab))
    end)
  end

  @doc "Decide next direction given an elevator state.
  Algorithm: continue in the current direction if there are any requests further in that direction; otherwise reverse if there are requests in the opposite direction; otherwise stop."
  @spec decide_next_direction(Elevator.State.t()) ::
          {:down, :door_open | :moving} | {:stop, :idle} | {:up, :moving}
  def decide_next_direction(%Elevator.State{
        orders: orders,
        direction: direction,
        floor: floor
      }) do
    if map_size(orders) == 0 do
      {:stop, :idle}
    else
      case direction do
        :up ->
          cond do
            requests_above?(orders, floor) -> {:up, :moving}
            request_here?(orders, floor) -> {:down, :door_open}
            requests_below?(orders, floor) -> {:down, :moving}
            true -> {:stop, :idle}
          end

        :down ->
          cond do
            requests_below?(orders, floor) -> {:down, :moving}
            request_here?(orders, floor) -> {:down, :door_open}
            requests_above?(orders, floor) -> {:up, :moving}
            true -> {:stop, :idle}
          end

        # there should only be one request in the Stop case. Checking up or down first is arbitrary.
        :stop ->
          cond do
            request_here?(orders, floor) -> {:down, :door_open}
            requests_above?(orders, floor) -> {:up, :moving}
            requests_below?(orders, floor) -> {:down, :moving}
            true -> {:stop, :idle}
          end

        _ ->
          {:stop, :idle}
      end
    end
  end

  @doc "Decide whether the elevator should stop at `floor` given current `dir` and `reqs`.
  Rules:
  - Stop if any `:cab` request for this floor.
  - Stop if there's a hall request for this floor in the direction of travel.
  - Stop if there are no further requests in the direction of travel (so we can turn around)."
  @spec should_stop?(Elevator.State.t()) :: boolean()
  def should_stop?(%Elevator.State{
        orders: orders,
        direction: direction,
        floor: floor
      }) do
    btns = Map.get(orders, floor, MapSet.new())

    case direction do
      :down ->
        MapSet.member?(btns, :hall_down) or
          MapSet.member?(btns, :cab) or
          not requests_below?(orders, floor)

      :up ->
        MapSet.member?(btns, :hall_up) or
          MapSet.member?(btns, :cab) or
          not requests_above?(orders, floor)

      :stop ->
        true

      _ ->
        true
    end
  end

  @doc "Clear requests at `floor` from the `reqs` map according to the direction of travel.
  Clears cab orders always, and hall orders only in the matching direction."
  @spec clear_orders_at_current_floor(Elevator.State.t()) :: Elevator.State.t()
  def clear_orders_at_current_floor(
        %Elevator.State{
          orders: orders,
          direction: direction,
          floor: floor
        } = elevator_state
      ) do
    btns = Map.get(orders, floor, MapSet.new())

    # always clear cab
    remaining = MapSet.delete(btns, :cab)

    # Clear hall buttons based on direction
    remaining =
      case direction do
        :up -> MapSet.delete(remaining, :hall_up)
        :down -> MapSet.delete(remaining, :hall_down)
        :stop -> remaining |> MapSet.delete(:hall_up) |> MapSet.delete(:hall_down)
        _ -> remaining
      end

    new_orders =
      if MapSet.size(remaining) == 0,
        do: Map.delete(orders, floor),
        else: Map.put(orders, floor, remaining)

    %{elevator_state | orders: new_orders}
  end
end
