defmodule Elevator.Types do
  @moduledoc """
    Different types for the elevator
  """
  @type floor :: 0 | 1 | 2 | 3

  @type btn_dir :: :up | :down

  @type elev_dir :: :up | :down | :stop

  @type elev_state :: :moving | :idle | :door_open

  @type hall_order_value ::
  :unknown
  | :idle
  | {:pending, MapSet.t()}
  | {:confirmed, map(), MapSet.t()}

  @type hall_order_map :: %{
    {floor(), btn_dir()} => hall_order_value()
  }

  @type cab_order_value :: %{
    version: non_neg_integer(),
    orders: MapSet.t()
  }

  @type cab_order_map :: %{
    node() => cab_order_value()
  }
end
