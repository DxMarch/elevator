defmodule Elevator.Application do
  use Application

  def start(_start_type, _start_args) do
    children = [
      Elevator.CabOrders,
      Elevator.HallOrders
    ]

    start_fsm_and_driver? = Application.get_env(:elevator, :start_fsm_and_driver, true)

    children =
        if start_fsm_and_driver? do
          [Elevator.Driver, Elevator.DriverPoller, Elevator.FSM | children]
        else
          children
        end

    opts = [strategy: :one_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
