defmodule Elevator do
  @num_floors 4
  @door_open_duration_ms 1000

  @spec num_floors() :: pos_integer()
  def num_floors do
    @num_floors
  end

  @spec door_open_duration_ms() :: pos_integer()
  def door_open_duration_ms do
    @door_open_duration_ms
  end
end
