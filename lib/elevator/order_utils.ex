defmodule Elevator.OrderUtils do
  @moduledoc """
  Pure functions for elevator order manipulation.

  These functions are intentionally pure to make them easy to unit test.
  """

  @type combined_order_map :: %{
          Elevator.floor() => MapSet.t(Elevator.button_type())
        }

  @spec orders_above?(combined_order_map(), Elevator.floor()) :: boolean()
  def orders_above?(reqs, floor) do
    Enum.any?(reqs, fn {f, _} -> f > floor end)
  end

  @spec orders_below?(combined_order_map(), Elevator.floor()) :: boolean()
  def orders_below?(reqs, floor) do
    Enum.any?(reqs, fn {f, _} -> f < floor end)
  end

  @spec combine_hall_and_cab(
          combined_order_map(),
          MapSet.t(Elevator.floor())
        ) :: combined_order_map()
  def combine_hall_and_cab(hall_orders, cab_floors) do
    Enum.reduce(cab_floors, hall_orders, fn floor, acc ->
      Map.update(acc, floor, MapSet.new([:cab]), &MapSet.put(&1, :cab))
    end)
  end
end
