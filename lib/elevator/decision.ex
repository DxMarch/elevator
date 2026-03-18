defmodule Elevator.Decision do
  @moduledoc """
  Pure functions for elevator request manipulation.

  These functions are intentionally pure to make them easy to unit test.
  """

  @spec requests_above?(Elevator.combined_order_map(), Elevator.floor()) :: boolean()
  def requests_above?(reqs, floor) do
    Enum.any?(reqs, fn {f, _} -> f > floor end)
  end

  @spec requests_below?(Elevator.combined_order_map(), Elevator.floor()) :: boolean()
  def requests_below?(reqs, floor) do
    Enum.any?(reqs, fn {f, _} -> f < floor end)
  end

  @spec combine_hall_and_cab(
          Elevator.combined_order_map(),
          MapSet.t(Elevator.floor())
        ) :: Elevator.combined_order_map()
  def combine_hall_and_cab(hall_orders, cab_floors) do
    Enum.reduce(cab_floors, hall_orders, fn floor, acc ->
      Map.update(acc, floor, MapSet.new([:cab]), &MapSet.put(&1, :cab))
    end)
  end

  @doc "Single decision function for elevator behavior.
  Returns both direction and behavior for the current state and order snapshot."
  @spec next_action(Elevator.combined_order_map(), Elevator.FSM.State.t()) ::
          {:up | :down, :moving | :door_open | :idle}
  def next_action(
        orders,
        %Elevator.FSM.State{
          direction: direction,
          floor: floor,
          between_floors: between_floors
        }
      ) do
    btns_at_floor = Map.get(orders, floor, MapSet.new())
    direction = if direction in [:up, :down], do: direction, else: :down

    cond do
      between_floors ->
        {direction, :moving}

      map_size(orders) == 0 ->
        {direction, :idle}

      direction == :up ->
        cond do
          MapSet.member?(btns_at_floor, :hall_up) or MapSet.member?(btns_at_floor, :cab) ->
            {:up, :door_open}

          requests_above?(orders, floor) ->
            {:up, :moving}

          MapSet.member?(btns_at_floor, :hall_down) ->
            {:down, :door_open}

          requests_below?(orders, floor) ->
            {:down, :moving}

          true ->
            {:up, :idle}
        end

      direction == :down ->
        cond do
          MapSet.member?(btns_at_floor, :hall_down) or MapSet.member?(btns_at_floor, :cab) ->
            {:down, :door_open}

          requests_below?(orders, floor) ->
            {:down, :moving}

          MapSet.member?(btns_at_floor, :hall_up) ->
            {:up, :door_open}

          requests_above?(orders, floor) ->
            {:up, :moving}

          true ->
            {:down, :idle}
        end

      true ->
        {:down, :idle}
    end
  end
end
