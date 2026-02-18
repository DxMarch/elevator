defmodule Elevator.Support.TestCompiled do
  def start_order_modules(num_floors) do
    children = [
      {Elevator.HallOrders, num_floors},
      Elevator.CabOrders
    ]
    opts = [strategy: :one_for_one, name: Elevator.Supervisor]
    case Supervisor.start_link(children, opts) do
      {:ok, pid} -> 
        Process.unlink(pid)
        {:ok, pid}
      error ->
        error
    end
  end
end
