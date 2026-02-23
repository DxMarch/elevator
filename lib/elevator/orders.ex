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

  @doc "Should a request at `btn_floor` and `btn_type` be cleared immediately given elevator state?"
  @spec should_clear_immediately?(
          Elevator.State.t(),
          Elevator.Types.floor(),
          Elevator.Types.btn_type()
        ) :: boolean()
  def should_clear_immediately?(
        %Elevator.State{floor: floor, direction: direction},
        btn_floor,
        btn_type
      ) do
    cond do
      floor != btn_floor -> false
      btn_type == :cab -> true
      direction == :up and btn_type == :hall_up -> true
      direction == :down and btn_type == :hall_down -> true
      direction == :stop -> true
      true -> false
    end
  end

  @spec combine_hall_and_cab(
          Elevator.Types.combined_order_map(),
          MapSet.t(Elevator.Types.floor())
        ) :: Elevator.Types.combined_order_map()
  def combine_hall_and_cab(hall_orders, cab_floors) do
    Enum.reduce(cab_floors, hall_orders, fn floor, acc ->
      Map.update(acc, floor, MapSet.new([:cab]), &MapSet.put(&1, :cab))
    end)
  end

  @doc "Decide next direction given an elevator state.
  Algorithm: continue in the current direction if there are any requests further in that direction; otherwise reverse if there are requests in the opposite direction; otherwise stop."
  @spec decide_next_direction(Elevator.Types.combined_order_map(), Elevator.State.t()) ::
          {:down, :moving | :door_open}
          | {:up, :moving | :door_open}
          | {:stop, :idle | :door_open}
  def decide_next_direction(
        orders,
        %Elevator.State{
          direction: direction,
          floor: floor
        }
      ) do
    if map_size(orders) == 0 do
      {:stop, :idle}
    else
      case direction do
        :up ->
          btns = Map.get(orders, floor, MapSet.new())

          cond do
            requests_above?(orders, floor) -> {:up, :moving}
            MapSet.member?(btns, :hall_up) or MapSet.member?(btns, :cab) -> {:up, :door_open}
            MapSet.member?(btns, :hall_down) -> {:down, :door_open}
            requests_below?(orders, floor) -> {:down, :moving}
            true -> {:stop, :idle}
          end

        :down ->
          btns = Map.get(orders, floor, MapSet.new())

          cond do
            requests_below?(orders, floor) -> {:down, :moving}
            MapSet.member?(btns, :hall_down) or MapSet.member?(btns, :cab) -> {:down, :door_open}
            MapSet.member?(btns, :hall_up) -> {:up, :door_open}
            requests_above?(orders, floor) -> {:up, :moving}
            true -> {:stop, :idle}
          end

        # there should only be one request in the Stop case. Checking up or down first is arbitrary.
        :stop ->
          btns = Map.get(orders, floor, MapSet.new())

          cond do
            MapSet.member?(btns, :hall_up) -> {:up, :door_open}
            MapSet.member?(btns, :hall_down) -> {:down, :door_open}
            MapSet.member?(btns, :cab) -> {:stop, :door_open}
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
  @spec should_stop?(Elevator.Types.combined_order_map(), Elevator.State.t()) :: boolean()
  def should_stop?(
        orders,
        %Elevator.State{
          direction: direction,
          floor: floor
        }
      ) do
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
end
