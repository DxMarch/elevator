defmodule Elevator.Hardware.Driver do
  @moduledoc """
  Handout driver from TTK4145 GitHub with minor modifications.

  Modifications:
  - Don't crash immediately if tcp connection fails. Retry connection periodically instead.
  - Added @spec declarations to public functions.
  - Changed magic numbers to atoms where applicable.
  """
  use GenServer
  require Logger

  @call_timeout_ms 1000
  @reconnect_interval_ms 1000
  @button_map %{hall_up: 0, hall_down: 1, cab: 2}
  @state_map %{on: 1, off: 0}
  @direction_map %{up: 1, down: 255, stop: 0}

  def start_link([address, port]) do
    GenServer.start_link(__MODULE__, [address, port], name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  @impl true
  def init([address, port]) do
    socket = connect(address, port)
    {:ok, {socket, address, port}}
  end

  defp connect(address, port) do
    case :gen_tcp.connect(address, port, [{:active, false}]) do
      {:ok, socket} ->
        Logger.info("Driver connected to elevator server at #{inspect(address)}:#{port}")
        socket

      {:error, reason} ->
        Logger.warning(
          "Driver failed to connect (#{reason}), retrying in #{@reconnect_interval_ms}ms..."
        )

        Process.sleep(@reconnect_interval_ms)
        connect(address, port)
    end
  end

  # User API ----------------------------------------------
  @spec set_motor_direction(:up | :down | :stop) :: :ok
  def set_motor_direction(direction) do
    GenServer.cast(__MODULE__, {:set_motor_direction, direction})
  end

  @spec set_order_button_light(:hall_up | :hall_down | :cab, non_neg_integer(), :on | :off) :: :ok
  def set_order_button_light(button_type, floor, state) do
    GenServer.cast(__MODULE__, {:set_order_button_light, button_type, floor, state})
  end

  @spec set_floor_indicator(non_neg_integer()) :: :ok
  def set_floor_indicator(floor) do
    GenServer.cast(__MODULE__, {:set_floor_indicator, floor})
  end

  @spec set_stop_button_light(:on | :off) :: :ok
  def set_stop_button_light(state) do
    GenServer.cast(__MODULE__, {:set_stop_button_light, state})
  end

  @spec set_door_open_light(:on | :off) :: :ok
  def set_door_open_light(state) do
    GenServer.cast(__MODULE__, {:set_door_open_light, state})
  end

  @spec get_order_button_state(non_neg_integer(), :hall_up | :hall_down | :cab) ::
          :active | :inactive
  def get_order_button_state(floor, button_type) do
    GenServer.call(__MODULE__, {:get_order_button_state, floor, button_type})
  end

  @spec get_floor_sensor_state() :: non_neg_integer() | :between_floors
  def get_floor_sensor_state do
    GenServer.call(__MODULE__, :get_floor_sensor_state)
  end

  @spec get_stop_button_state() :: :active | :inactive
  def get_stop_button_state do
    GenServer.call(__MODULE__, :get_stop_button_state)
  end

  @spec get_obstruction_switch_state() :: :active | :inactive
  def get_obstruction_switch_state do
    GenServer.call(__MODULE__, :get_obstruction_switch_state)
  end

  # Casts  ----------------------------------------------
  @impl true
  def handle_cast({:set_motor_direction, direction}, {socket, addr, port}) do
    :gen_tcp.send(socket, [1, @direction_map[direction], 0, 0])
    {:noreply, {socket, addr, port}}
  end

  @impl true
  def handle_cast({:set_order_button_light, button_type, floor, state}, {socket, addr, port}) do
    :gen_tcp.send(socket, [2, @button_map[button_type], floor, @state_map[state]])
    {:noreply, {socket, addr, port}}
  end

  @impl true
  def handle_cast({:set_floor_indicator, floor}, {socket, addr, port}) do
    :gen_tcp.send(socket, [3, floor, 0, 0])
    {:noreply, {socket, addr, port}}
  end

  @impl true
  def handle_cast({:set_door_open_light, state}, {socket, addr, port}) do
    :gen_tcp.send(socket, [4, @state_map[state], 0, 0])
    {:noreply, {socket, addr, port}}
  end

  @impl true
  def handle_cast({:set_stop_button_light, state}, {socket, addr, port}) do
    :gen_tcp.send(socket, [5, @state_map[state], 0, 0])
    {:noreply, {socket, addr, port}}
  end

  # Calls  ----------------------------------------------
  @impl true
  def handle_call({:get_order_button_state, floor, order_type}, _from, {socket, addr, port}) do
    :gen_tcp.send(socket, [6, @button_map[order_type], floor, 0])

    case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
      {:ok, [6, 0, 0, 0]} -> {:reply, :inactive, {socket, addr, port}}
      {:ok, [6, 1, 0, 0]} -> {:reply, :active, {socket, addr, port}}
    end
  end

  @impl true
  def handle_call(:get_floor_sensor_state, _from, {socket, addr, port}) do
    :gen_tcp.send(socket, [7, 0, 0, 0])

    case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
      {:ok, [7, 0, _, 0]} -> {:reply, :between_floors, {socket, addr, port}}
      {:ok, [7, 1, floor, 0]} -> {:reply, floor, {socket, addr, port}}
    end
  end

  @impl true
  def handle_call(:get_stop_button_state, _from, {socket, addr, port}) do
    :gen_tcp.send(socket, [8, 0, 0, 0])

    case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
      {:ok, [8, 0, 0, 0]} -> {:reply, :inactive, {socket, addr, port}}
      {:ok, [8, 1, 0, 0]} -> {:reply, :active, {socket, addr, port}}
    end
  end

  @impl true
  def handle_call(:get_obstruction_switch_state, _from, {socket, addr, port}) do
    :gen_tcp.send(socket, [9, 0, 0, 0])

    case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
      {:ok, [9, 0, 0, 0]} -> {:reply, :inactive, {socket, addr, port}}
      {:ok, [9, 1, 0, 0]} -> {:reply, :active, {socket, addr, port}}
    end
  end
end
