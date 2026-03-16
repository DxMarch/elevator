defmodule Elevator.Communicator do
  @moduledoc """
  Module responsible for all communication with other elevators.
  """

  alias Elevator
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

    :net_kernel.monitor_nodes(true)

    state = %{
      operational: true,
      connected_nodes:
        Map.from_keys(Node.list(:connected), %{operational: true, timestamp: Time.utc_now()})
    }

    {:ok, state}
  end

  @doc """
  Returns the ID of this node.
  """
  @spec my_id() :: node_id_t()
  # TODO: decide on this
  def my_id, do: Node.self()

  @doc """
  Returns a set of alive nodes that are both:
  a) Connected
  AND
  b) Have sent a message within the cutoff period
  """
  @spec who_can_serve() :: MapSet.t()
  def who_can_serve do
    GenServer.call(__MODULE__, :who_can_serve)
  end

  @doc """
  Updates the operational key in the state map.
  """
  @spec update_operation_status(boolean()) :: :ok
  def update_operation_status(status) do
    GenServer.cast(__MODULE__, {:update_operation_status, status})
  end

  # Updates the timestamp when a message is recieved from a node
  @spec update_state_map(state_t(), node_id_t(), boolean()) :: state_t()
  defp update_state_map(state, from_node, operational) do
    from_node_map = %{operational: operational, timestamp: Time.utc_now()}
    %{state | connected_nodes: Map.put(state.connected_nodes, from_node, from_node_map)}
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
      Task.start(fn ->
        cab_state = CabOrders.get_state()
        hall_state = HallOrders.get_state()

        Node.list(:connected)
        |> GenServer.abcast(
          __MODULE__,
          {:state_update, my_id(), state.operational, hall_state, cab_state}
        )
      end)
    end

    {:noreply, state}
  end

  # Update the state map when a new node connects
  def handle_info({:nodeup, node}, state) do
    {:noreply, update_state_map(state, node, true)}
  end

  # Delete node from state map on disconnect
  def handle_info({:nodedown, node}, state) do
    {:noreply, %{state | connected_nodes: Map.delete(state.connected_nodes, node)}}
  end

  def handle_info(:log_debug, state) do
    Process.send_after(self(), :log_debug, 1000)
    Logger.debug("My id: #{my_id()}")
    others = who_can_serve() |> Enum.map(fn x -> "#{x}" end) |> Enum.join(", ")
    Logger.debug("Others: #{others}")
    {:noreply, state}
  end

  # --- Handle calls ---

  def handle_call(:self, _, state) do
    {:reply, my_id(), state}
  end

  def handle_call(:who_can_serve, _from, state) do
    cutoff_ms = Elevator.msg_ts_cutoff()

    communicating_nodes =
      state.connected_nodes
      |> Map.filter(fn {_k, %{operational: operational, timestamp: timestamp}} ->
        Time.diff(Time.utc_now(), timestamp, :millisecond) < cutoff_ms and operational
      end)
      |> Map.keys()
      |> MapSet.new()

    operational_nodes =
      if state.operational do
        MapSet.put(communicating_nodes, my_id())
      else
        communicating_nodes
      end

    {:reply, operational_nodes, state}
  end

  # --- Handle casts ---

  @doc """
  Sends received hall and cab orders to respective modules, and updates timestamps for when the connected nodes last sent something.
  """
  @spec handle_cast(
          {:state_update, node_id_t(), boolean(), hall_orders_t(), cab_orders_t()},
          state_t()
        ) ::
          {:noreply, state_t()}
  def handle_cast({:state_update, from, operational, hall_orders, cab_orders}, state) do
    HallOrders.receive_state(hall_orders)
    CabOrders.receive_state(cab_orders)
    new_state = update_state_map(state, from, operational)
    {:noreply, new_state}
  end

  @spec handle_cast({:update_operation_status, boolean()}, state_t()) :: state_t()
  def handle_cast({:update_operation_status, status}, state) do
    {:noreply, %{state | operational: status}}
  end
end
