defmodule Elevator do
  @num_floors Application.compile_env(:elevator, :num_floors, 4)
  @resend_period_ms 50
  @msg_cutoff_ms 10000
  def num_floors do
    @num_floors
  end

  def resend_period_ms do
    @resend_period_ms
  end

  def msg_cutoff_ms do
    @msg_cutoff_ms
  end

  def time_to_serve_executable do
    {:ok, path} = Application.fetch_env(:elevator, :time_to_serve_executable)
    path
  end
end
