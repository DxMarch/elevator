defmodule Elevator do
  @num_floors Application.compile_env(:elevator, :num_floors, 4)

  def num_floors do
    @num_floors
  end
end
