defmodule Elevator.Types do
  @moduledoc """
    Different type definitions for the elevator
  """
  @type floor :: non_neg_integer()

  @type btn_dir :: :up | :down

  @type elev_dir :: :up | :down

  @type elev_behavior :: :moving | :idle | :door_open

  @type hall_btn :: :hall_down | :hall_up

  @type btn_type :: :cab | hall_btn()

  @spec btn_types() :: [btn_type()]
  def btn_types(), do: [:hall_up, :hall_down, :cab]

  @type hall_order_key :: {floor(), hall_btn()}

  @type hall_order_state ::
          :idle
          | {:pending, MapSet.t()}
          | {:handling, %{Node.t() => integer()}}
          | {:arrived, MapSet.t()}

  @type hall_order_map :: %{
          hall_order_key() => hall_order_state()
        }

  @type cab_orders_snapshot :: %{
          version: non_neg_integer(),
          orders: MapSet.t(floor())
        }

  @type cab_order_map :: %{
          Node.t() => cab_orders_snapshot()
        }

  @type combined_order_map :: %{
          floor() => MapSet.t(btn_type())
        }

  @type communicator_state_map :: %{
          operational: boolean(),
          connected_nodes: %{Node.t() => %{operational: boolean(), timestamp: Time.t()}}
        }

  @type communicator_message :: %{
          from: Node.t(),
          operational: boolean(),
          hall_order_map: hall_order_map(),
          cab_order_map: cab_order_map()
        }
end
