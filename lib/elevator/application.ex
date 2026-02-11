defmodule Elevator.Application do
  use Application

  def start(_start_type, _start_args) do
    # TODO: Start supervisor
    {:ok, self()}
  end
end
