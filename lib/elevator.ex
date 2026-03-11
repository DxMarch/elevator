defmodule Elevator do
  @num_floors Application.compile_env(:elevator, :num_floors, 4)
  # ms
  @resend_period 50
  @light_period 50
  @msg_ts_cutoff 1000
  @test_convergence_wait_time 3 * @resend_period

  def num_floors do
    @num_floors
  end

  def resend_period do
    @resend_period
  end

  def light_period do
    @light_period
  end

  def msg_ts_cutoff do
    @msg_ts_cutoff
  end

  def test_convergence_wait_time do
    @test_convergence_wait_time
  end
end
