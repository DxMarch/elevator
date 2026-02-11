defmodule Elevator.Communicator do
  use GenServer
  @moduledoc """
  Module responsible for all communication with other elevators.
  """

  def handle_cast(:state_update, state) do
    # "Decode" the state from the other node
    # Send cab and hall order states to respective modules
  end

  defp handle_info(:work, state) do
    # Ask cab_orders for state
    # Ask hall_orderes for state
    # Merge to state type and send to other nodes
    schedule_work()
    # {:noreply, new_state}
  end

  defp schedule_work do
    Process.send_after(self(), :work, 500) # TODO: set appropriate time
  end
end
