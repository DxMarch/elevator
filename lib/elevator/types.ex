defmodule Elevator.Types do
  @moduledoc """
    Different type definitions for the elevator
  """
  @type floor :: non_neg_integer()

  @type btn_dir :: :up | :down

  @type elev_dir :: :up | :down | :stop

  @type elev_state :: :moving | :idle | :door_open

  @type hall_btn :: :hall_down | :hall_up

  @type btn_type :: :cab | hall_btn()

  @spec btn_types() :: [btn_type()]
  def btn_types(), do: [:hall_up, :hall_down, :cab]

  @type hall_order_value ::
          :unknown
          | :idle
          | {:pending, MapSet.t()}
          | {:confirmed, map(), MapSet.t()}

  @type hall_order_map :: %{
          {floor(), hall_btn()} => hall_order_value()
        }

  @type cab_orders_snapshot :: %{
          version: non_neg_integer(),
          orders: MapSet.t()
        }

  @type cab_order_map :: %{
          node() => cab_orders_snapshot()
        }

  @type combined_order_map :: %{
          floor() => MapSet.t(btn_type())
        }
end
