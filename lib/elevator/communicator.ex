defmodule Elevator.Communicator do
  @moduledoc """
  Module responsible for all communication with other elevators.
  """

  alias Elevator.CabOrders
  alias Elevator.HallOrders
  use GenServer

  @type node_id_t :: Elevator.Types.node_id()
  @type hall_orders_t :: Elevator.Types.hall_order_map()
  @type cab_orders_t :: Elevator.Types.cab_order_map()
  @type state_t :: nil

  @type communicator_options :: [do_resend: boolean()]

  def start_link(arg \\ [do_resend: true]) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec init(communicator_options()) :: {:ok, state_t()}
  def init(opts \\ [do_resend: true]) do
    if Keyword.get(opts, :do_resend, true) do
      schedule_state_broadcast()
    end
    {:ok, nil}
  end

  @doc """
  Returns the ID of this node.
  """
  @spec my_id() :: node_id_t()
  def my_id, do: Node.self()

  @spec who_is_alive() :: MapSet.t()
  def who_is_alive do
    MapSet.new([Node.self()] ++ Node.list(:connected))
  end

  # Schedules another round of state broadcasting.
  defp schedule_state_broadcast do
    time_ms = Elevator.resend_period() # TODO: set appropriate time
    Process.send_after(self(), :broadcast_state, time_ms)
  end

  @doc """
  Sends the cab and hall state to all connected nodes.
  """
  def handle_info(:broadcast_state, id) do
    schedule_state_broadcast() # For periodic execution
    cab_state = CabOrders.get_state()
    hall_state = HallOrders.get_state()

    Node.list(:connected)
    |> Enum.each(fn ext_node ->
      GenServer.cast({__MODULE__, ext_node}, {:state_update, hall_state, cab_state}) end)

    {:noreply, id}
  end

  # --- Handle calls ---

  def handle_call(:self, _, id) do
    # TODO: Figure out if Node.self() is OK
    {:reply, Node.self(), id}
  end


  # --- Handle casts ---

  @spec handle_cast({:state_update, hall_orders_t(), cab_orders_t()}, state_t()) :: {:noreply, state_t()}
  def handle_cast({:state_update, hall_orders, cab_orders}, id) do
    HallOrders.receive_state(hall_orders)
    CabOrders.receive_state(cab_orders)
    {:noreply, id}
  end
end
