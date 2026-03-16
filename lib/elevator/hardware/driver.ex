defmodule Elevator.Hardware.Driver do
  use GenServer
  @call_timeout_ms 1000
  @button_map %{:hall_up => 0, :hall_down => 1, :cab => 2}
  @state_map %{:on => 1, :off => 0}
  @direction_map %{:up => 1, :down => 255, :stop => 0}

  def start_link([]) do
    start_link([{127, 0, 0, 1}, 15657])
  end

  def start_link([address, port]) do
    GenServer.start_link(__MODULE__, [address, port], name: __MODULE__)
  end

  def stop do
    GenServer.stop(__MODULE__)
  end

  @impl true
  def init([address, port]) do
    {:ok, socket} = :gen_tcp.connect(address, port, [{:active, false}])
    {:ok, socket}
  end

  # User API ----------------------------------------------
  @doc """
  Sets the motor direction.

  ## Parameters
  - direction: :up, :down, or :stop
  """
  def set_motor_direction(direction) do
    GenServer.cast(__MODULE__, {:set_motor_direction, direction})
  end

  @doc """
  Sets the light for an order button.

  ## Parameters
  - button_type: :hall_up, :hall_down, or :cab
  - floor: floor number (integer)
  - state: :on or :off
  """
  def set_order_button_light(button_type, floor, state) do
    GenServer.cast(__MODULE__, {:set_order_button_light, button_type, floor, state})
  end

  @doc """
  Sets the floor indicator display.

  ## Parameters
  - floor: floor number to display (integer)
  """
  def set_floor_indicator(floor) do
    GenServer.cast(__MODULE__, {:set_floor_indicator, floor})
  end

  @doc """
  Sets the stop button light.

  ## Parameters
  - state: :on or :off
  """
  def set_stop_button_light(state) do
    GenServer.cast(__MODULE__, {:set_stop_button_light, state})
  end

  @doc """
  Sets the door open indicator light.

  ## Parameters
  - state: :on or :off
  """
  def set_door_open_light(state) do
    GenServer.cast(__MODULE__, {:set_door_open_light, state})
  end

  @doc """
  Gets the state of an order button.

  ## Parameters
  - floor: floor number (integer)
  - button_type: :hall_up, :hall_down, or :cab

  ## Returns
  - :active if button is pressed
  - :inactive if button is not pressed
  """
  def get_order_button_state(floor, button_type) do
    GenServer.call(__MODULE__, {:get_order_button_state, floor, button_type})
  end

  @doc """
  Gets the current floor from the floor sensor.

  ## Returns
  - floor number (integer) if elevator is at a floor
  - :between_floors if elevator is between floors
  """
  def get_floor_sensor_state do
    GenServer.call(__MODULE__, :get_floor_sensor_state)
  end

  @doc """
  Gets the state of the stop button.

  ## Returns
  - :active if stop button is pressed
  - :inactive if stop button is not pressed
  """
  def get_stop_button_state do
    GenServer.call(__MODULE__, :get_stop_button_state)
  end

  @doc """
  Gets the state of the obstruction switch (door sensor).

  ## Returns
  - :active if obstruction is detected
  - :inactive if no obstruction
  """
  def get_obstruction_switch_state do
    GenServer.call(__MODULE__, :get_obstruction_switch_state)
  end

  @doc """
  Checks if the driver GenServer is running.

  Note: This only checks if the GenServer process is alive, not if the TCP
  connection is active. The driver will crash and restart automatically
  if the connection fails during operation.

  ## Returns
  - :ok if the GenServer is running
  - {:error, :not_connected} if the state is not a valid socket (should rarely occur)
  """
  def ping do
    GenServer.call(__MODULE__, :ping)
  end

  # Casts  ----------------------------------------------
  @impl true
  def handle_cast({:set_motor_direction, direction}, socket) do
    :gen_tcp.send(socket, [1, @direction_map[direction], 0, 0])
    {:noreply, socket}
  end

  @impl true
  def handle_cast({:set_order_button_light, button_type, floor, state}, socket) do
    :gen_tcp.send(socket, [2, @button_map[button_type], floor, @state_map[state]])
    {:noreply, socket}
  end

  @impl true
  def handle_cast({:set_floor_indicator, floor}, socket) do
    :gen_tcp.send(socket, [3, floor, 0, 0])
    {:noreply, socket}
  end

  @impl true
  def handle_cast({:set_door_open_light, state}, socket) do
    :gen_tcp.send(socket, [4, @state_map[state], 0, 0])
    {:noreply, socket}
  end

  @impl true
  def handle_cast({:set_stop_button_light, state}, socket) do
    :gen_tcp.send(socket, [5, @state_map[state], 0, 0])
    {:noreply, socket}
  end

  # Calls  ----------------------------------------------
  @impl true
  def handle_call({:get_order_button_state, floor, order_type}, _from, socket) do
    :gen_tcp.send(socket, [6, @button_map[order_type], floor, 0])

    button_state =
      case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
        {:ok, [6, 0, 0, 0]} -> :inactive
        {:ok, [6, 1, 0, 0]} -> :active
      end

    {:reply, button_state, socket}
  end

  @impl true
  def handle_call(:get_floor_sensor_state, _from, socket) do
    :gen_tcp.send(socket, [7, 0, 0, 0])

    floor_state =
      case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
        {:ok, [7, 0, _, 0]} -> :between_floors
        {:ok, [7, 1, floor, 0]} -> floor
      end

    {:reply, floor_state, socket}
  end

  @impl true
  def handle_call(:get_stop_button_state, _from, socket) do
    :gen_tcp.send(socket, [8, 0, 0, 0])

    stop_state =
      case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
        {:ok, [8, 0, 0, 0]} -> :inactive
        {:ok, [8, 1, 0, 0]} -> :active
      end

    {:reply, stop_state, socket}
  end

  @impl true
  def handle_call(:get_obstruction_switch_state, _from, socket) do
    :gen_tcp.send(socket, [9, 0, 0, 0])

    obstruction_state =
      case :gen_tcp.recv(socket, 4, @call_timeout_ms) do
        {:ok, [9, 0, 0, 0]} -> :inactive
        {:ok, [9, 1, 0, 0]} -> :active
      end

    {:reply, obstruction_state, socket}
  end

  @impl true
  def handle_call(:ping, _from, socket) when is_port(socket) do
    {:reply, :ok, socket}
  end

  @impl true
  def handle_call(:ping, _from, socket) do
    {:reply, {:error, :not_connected}, socket}
  end
end
