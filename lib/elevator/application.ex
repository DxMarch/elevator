defmodule Elevator.Application do
  use Application

  def start(_start_type, _start_args) do
    children = [
      Elevator.Driver,
      Elevator.DriverPoller,
      Elevator.FSM,
      Elevator.CabOrders
    ]

    opts = [strategy: :one_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
