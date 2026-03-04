defmodule Elevator do
  @num_floors Application.compile_env(:elevator, :num_floors, 4)
  # ms
  @resend_period 10
  @light_period 50

  def num_floors do
    @num_floors
  end

  def resend_period do
    @resend_period
  end

  def light_period do
    @light_period
  end
end
