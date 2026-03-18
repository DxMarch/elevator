defmodule Elevator.Communicator do
  @moduledoc """
  Module responsible for all communication with other elevators.
  """

  alias Elevator
  alias Elevator.CabOrders
  alias Elevator.HallOrders

  require Logger
  use GenServer

  @type state_map :: Elevator.Types.communicator_state_map()

  @type communicator_message :: Elevator.Types.communicator_message()
  @type communicator_options :: [do_resend: boolean()]

  @resend_period_ms 50
  @msg_cutoff_ms 10000

  @spec start_link(communicator_options()) :: GenServer.on_start()
  def start_link(arg \\ [do_resend: true]) do
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(opts \\ [do_resend: true]) do
    if Keyword.get(opts, :do_resend, true) do
      schedule_broadcast_orders()
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
  Returns a set of alive nodes that are both:
  a) Connected
  b) Have sent a message within the cutoff period
  c) Have operational == true
  """
  @spec who_can_serve() :: MapSet.t(Node.t())
  def who_can_serve, do: GenServer.call(__MODULE__, :who_can_serve)

  @doc """
  Returns a set of alive nodes that are both:
  a) Connected
  b) Have sent a message within the cutoff period
  """
  @spec who_is_alive() :: MapSet.t(Node.t())
  def who_is_alive, do: GenServer.call(__MODULE__, :who_is_alive)

  @doc """
  Updates the `operational` part of the state.
  Signals to peers whether this node can serve orders.
  """
  @spec update_operation_status(boolean()) :: :ok
  def update_operation_status(status),
    do: GenServer.cast(__MODULE__, {:update_operation_status, status})

  # Infos --------------------------------------------------

  @doc """
  Sends the cab and hall state to all connected nodes.
  """
  @impl true
  def handle_info(:broadcast_orders, state) do
    schedule_broadcast_orders()

    if Process.whereis(CabOrders) && Process.whereis(HallOrders) do
      # Start a separate task to avoid this blocking the communicator.
      Task.start(fn ->
        message = %{
          from: Node.self(),
          operational: state.operational,
          hall_order_map: HallOrders.get_state(),
          cab_order_map: CabOrders.get_state()
        }

        Node.list(:connected)
        |> GenServer.abcast(__MODULE__, {:receive_external_message, message})
      end)
    end

    {:noreply, state}
  end

  # Update the state map when a new node connects
  @impl true
  def handle_info({:nodeup, node}, state) do
    {:noreply, update_node_timestamp(state, node, true)}
  end

  # Delete node from state map on disconnect
  @impl true
  def handle_info({:nodedown, node}, state) do
    {:noreply, %{state | connected_nodes: Map.delete(state.connected_nodes, node)}}
  end

  # Calls --------------------------------------------------

  @impl true
  def handle_call(:who_can_serve, _from, state) do
    operational_nodes =
      get_communicating_nodes(state)
      |> Enum.filter(fn node -> state.connected_nodes[node].operational end)
      |> MapSet.new()

    operational_nodes =
      if state.operational,
        do: MapSet.put(operational_nodes, Node.self()),
        else: operational_nodes

    {:reply, operational_nodes, state}
  end

  @impl true
  def handle_call(:who_is_alive, _from, state) do
    communicating_nodes = get_communicating_nodes(state)
    communicating_nodes = MapSet.put(communicating_nodes, Node.self())
    {:reply, communicating_nodes, state}
  end

  # Casts --------------------------------------------------

  @doc """
  Sends received hall and cab orders to respective modules, and updates timestamps for when the connected nodes last sent something.
  """
  @impl true
  @spec handle_cast({:receive_external_message, communicator_message()}, state_map()) ::
          {:noreply, state_map()}
  def handle_cast({:receive_external_message, msg}, state) do
    HallOrders.receive_external(msg.hall_order_map)
    CabOrders.receive_external(msg.cab_order_map)

    new_state = update_node_timestamp(state, msg.from, msg.operational)

    {:noreply, new_state}
  end

  @impl true
  @spec handle_cast({:update_operation_status, boolean()}, state_map()) :: {:noreply, state_map()}
  def handle_cast({:update_operation_status, status}, state) do
    {:noreply, %{state | operational: status}}
  end

  # Helpers --------------------------------------------------

  @spec get_communicating_nodes(state_map()) :: MapSet.t(Node.t())
  defp get_communicating_nodes(state) do
    state.connected_nodes
    |> Map.filter(fn {_k, %{timestamp: timestamp}} ->
      Time.diff(Time.utc_now(), timestamp, :millisecond) < @msg_cutoff_ms
    end)
    |> Map.keys()
    |> MapSet.new()
  end

  # Updates the timestamp when a message is received from a node
  @spec update_node_timestamp(state_map(), Node.t(), boolean()) :: state_map()
  defp update_node_timestamp(state, from_node, operational) do
    from_node_map = %{operational: operational, timestamp: Time.utc_now()}
    %{state | connected_nodes: Map.put(state.connected_nodes, from_node, from_node_map)}
  end

  defp schedule_broadcast_orders,
    do: Process.send_after(self(), :broadcast_orders, @resend_period_ms)
end
