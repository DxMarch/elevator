defmodule Elevator do
  @num_floors 4
  @door_open_duration_ms 1000
  # ms
  @resend_period 50
  @msg_ts_cutoff 10000
  @test_convergence_wait_time 3 * @resend_period

  def num_floors do
    @num_floors
  end

  def door_open_duration_ms do
    @door_open_duration_ms
  end

  def resend_period do
    @resend_period
  end

  def msg_ts_cutoff do
    @msg_ts_cutoff
  end

  def test_convergence_wait_time do
    @test_convergence_wait_time
  end

  def time_to_serve_executable do
    {:ok, path} = Application.fetch_env(:elevator, :time_to_serve_executable)
    path
  end
end
