defmodule Elevator do
  @type floor :: non_neg_integer()

  @type button_type :: :cab | Elevator.HallOrders.hall_button_type()

  @type combined_order_map :: %{
          floor() => MapSet.t(button_type())
        }

  @num_floors 4
  @door_open_duration_ms 1000

  @spec num_floors() :: pos_integer()
  def num_floors(), do: @num_floors

  @spec door_open_duration_ms() :: pos_integer()
  def door_open_duration_ms(), do: @door_open_duration_ms

  @spec button_types() :: [button_type()]
  def button_types(), do: [:hall_up, :hall_down, :cab]
end
