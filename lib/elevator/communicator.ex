defmodule Elevator.Communicator do
  @moduledoc """
  Module responsible for all communication with other elevators.
  """

  alias Elevator.FSM.State
  alias Elevator
  alias Elevator.CabOrders
  alias Elevator.HallOrders

  require Logger
  use GenServer

  @type hall_order_map :: Elevator.HallOrders.hall_order_map()
  @type cab_order_map :: Elevator.CabOrders.cab_order_map()

  @type peer_status_map :: %{
          Node.t() => %{operational: boolean(), timestamp: Time.t()}
        }

  @type communicator_message :: %{
          from: Node.t(),
          operational: boolean(),
          hall_order_map: hall_order_map(),
          cab_order_map: cab_order_map()
        }

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

    peer_status_map =
      Map.from_keys(Node.list(:connected), %{operational: true, timestamp: Time.utc_now()})

    {:ok, peer_status_map}
  end

  @doc """
  Returns a set of alive nodes that are both:
  a) Connected
  b) Have sent a message within the cutoff period
  c) Have operational == true
  """
  @spec who_can_serve() :: MapSet.t(Node.t())
  def who_can_serve(), do: GenServer.call(__MODULE__, :who_can_serve)

  @doc """
  Returns a set of alive nodes that are both:
  a) Connected
  b) Have sent a message within the cutoff period
  """
  @spec who_is_alive() :: MapSet.t(Node.t())
  def who_is_alive(), do: GenServer.call(__MODULE__, :who_is_alive)

  # Infos --------------------------------------------------

  @doc """
  Sends the cab and hall state to all connected nodes.
  """
  @impl true
  def handle_info(:broadcast_orders, peer_status_map) do
    schedule_broadcast_orders()

    if Process.whereis(CabOrders) && Process.whereis(HallOrders) do
      # Start a separate task to avoid this blocking the communicator.
      Task.start(fn ->
        message = %{
          from: Node.self(),
          operational: State.operational?(),
          hall_order_map: HallOrders.get_order_map(),
          cab_order_map: CabOrders.get_order_map()
        }

        Node.list(:connected)
        |> GenServer.abcast(__MODULE__, {:receive_external_message, message})
      end)
    end

    {:noreply, peer_status_map}
  end

  # Update the status map when a new node connects
  @impl true
  def handle_info({:nodeup, node}, peer_status_map) do
    {:noreply, update_node_timestamp(peer_status_map, node, true)}
  end

  # Delete node from status map on disconnect
  @impl true
  def handle_info({:nodedown, node}, peer_status_map) do
    {:noreply, Map.delete(peer_status_map, node)}
  end

  # Calls --------------------------------------------------

  @impl true
  def handle_call(:who_can_serve, _from, peer_status_map) do
    operational_nodes =
      get_communicating_nodes(peer_status_map)
      |> Enum.filter(fn node -> peer_status_map[node].operational end)
      |> MapSet.new()

    operational_nodes =
      if State.operational?(),
        do: MapSet.put(operational_nodes, Node.self()),
        else: operational_nodes

    {:reply, operational_nodes, peer_status_map}
  end

  @impl true
  def handle_call(:who_is_alive, _from, peer_status_map) do
    communicating_nodes = get_communicating_nodes(peer_status_map)
    communicating_nodes = MapSet.put(communicating_nodes, Node.self())
    {:reply, communicating_nodes, peer_status_map}
  end

  # Casts --------------------------------------------------

  @doc """
  Sends received hall and cab orders to respective modules, and updates timestamps for when the connected nodes last sent something.
  """
  @impl true
  @spec handle_cast({:receive_external_message, communicator_message()}, peer_status_map()) ::
          {:noreply, peer_status_map()}
  def handle_cast({:receive_external_message, msg}, peer_status_map) do
    HallOrders.receive_external(msg.hall_order_map)
    CabOrders.receive_external(msg.cab_order_map)

    new_peer_status_map = update_node_timestamp(peer_status_map, msg.from, msg.operational)
    {:noreply, new_peer_status_map}
  end

  # Helpers --------------------------------------------------

  @spec get_communicating_nodes(peer_status_map()) :: MapSet.t(Node.t())
  defp get_communicating_nodes(peer_status_map) do
    peer_status_map
    |> Map.filter(fn {_k, %{timestamp: timestamp}} ->
      Time.diff(Time.utc_now(), timestamp, :millisecond) < @msg_cutoff_ms
    end)
    |> Map.keys()
    |> MapSet.new()
  end

  # Updates the timestamp when a message is received from a node
  @spec update_node_timestamp(peer_status_map(), Node.t(), boolean()) :: peer_status_map()
  defp update_node_timestamp(peer_status_map, from_node, operational) do
    new_peer_status = %{operational: operational, timestamp: Time.utc_now()}
    Map.put(peer_status_map, from_node, new_peer_status)
  end

  defp schedule_broadcast_orders,
    do: Process.send_after(self(), :broadcast_orders, @resend_period_ms)
end
