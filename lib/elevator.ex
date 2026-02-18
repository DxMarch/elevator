defmodule Elevator do
  @num_floors 4
  @resend_period 10 # ms

  def num_floors do
    @num_floors
  end

  def resend_period do
    @resend_period
  end
end
