defmodule Elevator.State do
  defstruct [:hall_orders, :cab_orders]

  @type hall_order_map :: %{
    {non_neg_integer(), :up} => Elevator.State.Hall.t(),
    {non_neg_integer(), :down} => Elevator.State.Hall.t()
  }

  @type cab_order_map :: %{
    node() => Elevator.State.Cab.t()
  }

  @type t :: %__MODULE__{
    hall_orders: hall_order_map(),
    cab_orders: cab_order_map()
  }
end
