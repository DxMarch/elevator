defmodule Elevator do
  @num_floors Application.compile_env(:elevator, :num_floors, 4)
  # ms
  @resend_period 10
  @msg_ts_cutoff 1000

  def num_floors do
    @num_floors
  end

  def resend_period do
    @resend_period
  end

  def msg_ts_cutoff do
    @msg_ts_cutoff
  end
end
