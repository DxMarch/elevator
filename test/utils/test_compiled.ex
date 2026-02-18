defmodule Test.Utils.TestCompiled do
  @moduledoc """
  This module exists because to run :rpc-calls, the called code has to be compiled, not .exs.
  So put code here if it is the endpoint of an RPC for testing that is not suitable for lib/.
  """
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
