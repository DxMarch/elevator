defmodule Elevator.Communicator do
  use GenServer
  @moduledoc """
  Module responsible for all communication with other elevators.
  """
  def init(state) do
    schedule_work()
    {:ok, state}
  end

  def handle_cast(:state_update, state) do
    # "Decode" the state from the other node
    # Send cab and hall order states to respective modules
  end

  def who_is_alive() do
    Node.list()
  end

  def handle_info(:work, state) do
    # Ask cab_orders for state
    cab_state = GenServer.start_link(CabOrders, {:get, __MODULE__})
    # Ask hall_orderes for state
    hall_state = GenServer.start(HallOrders, {:get, __MODULE__})
    # Merge to state type and send to other nodes
    Node.list()
    |> Enum.each(fn(ext_node) -> GenServer.cast(ext_node, {cab_state, hall_state}) end)
    schedule_work()
    # {:noreply, new_state}
  end

  defp schedule_work do
    time_ms = 500
    Process.send_after(self(), :work, time_ms) # TODO: set appropriate time
  end
end
