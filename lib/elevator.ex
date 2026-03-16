defmodule Elevator do
  @num_floors 4
  @resend_period_ms 50
  @msg_cutoff_ms 10000
  @door_open_duration_ms 1000

  def num_floors do
    @num_floors
  end

  def door_open_duration_ms do
    @door_open_duration_ms
  end

  def resend_period_ms do
    @resend_period_ms
  end

  def msg_cutoff_ms do
    @msg_cutoff_ms
  end
end
