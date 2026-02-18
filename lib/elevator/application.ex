defmodule Elevator.Application do
  use Application

  def start(_start_type, _start_args) do
    children = [
      {Elevator.HallOrders, Elevator.num_floors()},
      Elevator.CabOrders,
      Elevator.Driver,
      Elevator.DriverPoller,
      Elevator.FSM
    ]

    opts = [strategy: :one_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
