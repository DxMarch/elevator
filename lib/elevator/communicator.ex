defmodule Elevator.Communicator do
  @moduledoc """
  Module responsible for all communication with other elevators.
  """

  alias Elevator.CabOrders
  alias Elevator.HallOrders

  require Logger
  use GenServer

  @type node_id_t :: Elevator.Types.node_id()
  @type hall_orders_t :: Elevator.Types.hall_order_map()
  @type cab_orders_t :: Elevator.Types.cab_order_map()
  @type state_t :: Elevator.Types.communicator_state_map()

  @type communicator_options :: [do_resend: boolean()]

  def start_link(arg \\ [do_resend: true]) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(opts \\ [do_resend: true, do_logging: false]) do
    if Keyword.get(opts, :do_resend, true) do
      schedule_state_broadcast()
    end

    if Keyword.get(opts, :do_logging, false) do
      Process.send_after(self(), :log_debug, 1000)
    end

    state = %{
      operational: true,
      connected_nodes: Map.from_keys(Node.list(:connected), Time.utc_now())
    }

    {:ok, state}
  end

  @doc """
  Returns the ID of this node.
  """
  @spec my_id() :: node_id_t()
  # TODO: decide on this
  def my_id, do: Node.self()

  @spec who_is_alive() :: MapSet.t()
  def who_is_alive do
    MapSet.new([Node.self()] ++ Node.list(:connected))
  end

  @doc """
  Updates the operational key in the state map.
  """
  @spec update_operation_status(boolean()) :: state_t()
  def update_operation_status(status) do
    GenServer.cast(__MODULE__, {:update_operation_status, status})
  end

  # Updates the timestamp when a message is recieved from a node
  @spec update_state_map(state_t(), node_id_t()) :: state_t()
  defp update_state_map(state, from_node) do
    %{state | connected_nodes: Map.put(state.connected_nodes, from_node, Time.utc_now())}
  end

  # Schedules another round of state broadcasting.
  defp schedule_state_broadcast do
    time_ms = Elevator.resend_period()
    Process.send_after(self(), :broadcast_state, time_ms)
  end

  @doc """
  Sends the cab and hall state to all connected nodes.
  """
  def handle_info(:broadcast_state, state) do
    # For periodic execution
    schedule_state_broadcast()

    if Process.whereis(CabOrders) && Process.whereis(HallOrders) do
      cab_state = CabOrders.get_state()
      hall_state = HallOrders.get_state()

      Node.list(:connected)
      |> Enum.each(fn ext_node ->
        GenServer.cast({__MODULE__, ext_node}, {:state_update, my_id(), hall_state, cab_state})
      end)
    end

    {:noreply, state}
  end

  def handle_info(:log_debug, state) do
    Process.send_after(self(), :log_debug, 1000)
    Logger.debug("My id: #{my_id()}")
    others = who_is_alive() |> Enum.map(fn x -> "#{x}" end) |> Enum.join(", ")
    Logger.debug("Others: #{others}")
    {:noreply, state}
  end

  # --- Handle calls ---

  def handle_call(:self, _, state) do
    {:reply, my_id(), state}
  end

  # --- Handle casts ---

  @doc """
  Sends received hall and cab orders to respective modules, and updates timestamps for when the connected nodes last sent something.
  """
  @spec handle_cast({:state_update, node_id_t(), hall_orders_t(), cab_orders_t()}, state_t()) ::
          {:noreply, state_t()}
  def handle_cast({:state_update, from, hall_orders, cab_orders}, state) do
    HallOrders.receive_state(hall_orders)
    CabOrders.receive_state(cab_orders)
    new_state = update_state_map(state, from)
    {:noreply, new_state}
  end

  @spec handle_cast({:update_operation_status, boolean()}, state_t()) :: state_t()
  def handle_cast({:update_operation_status, status}, state) do
    {:noreply, %{state | operational: status}}
  end
end
