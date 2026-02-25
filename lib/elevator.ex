defmodule Elevator do
  @num_floors Application.compile_env(:elevator, :num_floors, 4)
  # ms
  @resend_period 10

  def num_floors do
    @num_floors
  end

  def resend_period do
    @resend_period
  end
end
