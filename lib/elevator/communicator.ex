defmodule Elevator.Communicator do
  use GenServer
  @moduledoc """
  Module responsible for all communication with other elevators.
  """
  alias Elevator.CabOrders
  alias Elevator.HallOrders
  alias Elevator.Types

  def init(id) do
    schedule_work()
    {:ok, id}
  end

  def my_id(), do: GenServer.call(__MODULE__, :self)

  def handle_call(:self, _, id) do
    {:reply, id, id}
  end

  @spec handle_cast({:state_update, Types.hall_order_map(), Types.cab_order_map()}, Types.node_id()):: {:noreply, Types.node_id()}
  def handle_cast({:state_update, hall_orders, cab_orders}, id) do
    # "Decode" the state from the other node
    # Send cab and hall order states to respective modules

    GenServer.cast(HallOrders, {:update, hall_orders})
    GenServer.cast(CabOrders, {:update, cab_orders})
    HallOrders.receive_state(hall_orders)
    {:noreply, id}
  end

  def who_is_alive() do
    Node.list(:connected)
  end

  def handle_info(:work, id) do
    cab_state = GenServer.call(CabOrders, :get)
    hall_state = GenServer.call(HallOrders, :get)
    HallOrders.get_state()

    Node.list(:connected)
    |> Enum.each(fn(ext_node) ->
      GenServer.cast({__MODULE__, ext_node}, {cab_state, hall_state}) end)

    schedule_work()
    {:noreply, id}
  end

  defp schedule_work do
    time_ms = 500
    Process.send_after(self(), :work, time_ms) # TODO: set appropriate time
  end
end
