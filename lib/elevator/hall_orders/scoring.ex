defmodule Elevator.HallOrders.Scoring do
  @doc """
  Maybe even random numbers?
  """
  def compute_score(_hall_orders, _cab_orders) do
    :rand.uniform(10)
  end
end
