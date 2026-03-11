defmodule Elevator.FSM.State do
  @moduledoc """
  Module storing the elevator state.
  """
  require Logger
  alias Elevator.Hardware.Outputs
  alias Elevator.Hardware.Driver
  alias Elevator.Types

  defstruct direction: :stop,
            behavior: :idle,
            floor: :unknown,
            between_floors: true,
            obstructed: false,
            motor_timed_out: false,
            door_open_time: Time.utc_now(),
            last_floor_time: nil

  @type t :: %__MODULE__{
          direction: Types.elev_dir(),
          behavior: Types.elev_behavior(),
          floor: :unknown | Types.floor(),
          between_floors: boolean(),
          obstructed: boolean(),
          motor_timed_out: boolean(),
          door_open_time: Time.t(),
          last_floor_time: Time.t() | nil
        }

  use GenServer

  @impl true
  def init(_arg) do
    floor = Driver.get_floor_sensor_state()
    state = %Elevator.FSM.State{}

    state =
      if floor == :between_floors do
        %{state | direction: :down, behavior: :moving, between_floors: true}
      else
        %{state | floor: floor, between_floors: false}
      end

    {:ok, state, {:continue, :set_outputs}}
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # User API ----------------------------------------

  def set_floor(floor) do
    GenServer.cast(__MODULE__, {:set_floor, floor})
  end

  def set_obstruction(obstructed) do
    GenServer.cast(__MODULE__, {:set_obstruction, obstructed})
  end

  def set_direction(dir) do
    GenServer.cast(__MODULE__, {:set_direction, dir})
  end

  def set_behavior(behavior) do
    GenServer.cast(__MODULE__, {:set_behavior, behavior})
  end

  def open_door() do
    GenServer.cast(__MODULE__, :open_door)
  end

  def set_motor_timed_out(timed_out) do
    GenServer.call(__MODULE__, {:set_motor_timed_out, timed_out})
  end

  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  # Casts ----------------------------------------

  @impl true
  def handle_cast({:set_floor, floor}, state) do
    new_state =
      case floor do
        :between_floors ->
          %{state | between_floors: true}

        _ ->
          %{state | between_floors: false, floor: floor, last_floor_time: Time.utc_now()}
      end

    {:noreply, new_state, {:continue, :set_outputs}}
  end

  @impl true
  def handle_cast({:set_obstruction, obstructed}, state) do
    {:noreply, %{state | obstructed: obstructed}}
  end

  @impl true
  def handle_cast({:set_direction, dir}, state) do
    {:noreply, %{state | direction: dir}, {:continue, :set_outputs}}
  end

  @impl true
  def handle_cast({:set_behavior, behavior}, state) do
    {:noreply, %{state | behavior: behavior}, {:continue, :set_outputs}}
  end

  @impl true
  def handle_cast({:set_door_open_time, door_open_time}, state) do
    {:noreply, %{state | door_open_time: door_open_time}, {:continue, :set_outputs}}
  end

  @impl true
  def handle_cast(:open_door, state) do
    new_state =
      if state.between_floors do
        state
      else
        %{state | behavior: :door_open, door_open_time: Time.utc_now()}
      end

    {:noreply, new_state, {:continue, :set_outputs}}
  end

  @impl true
  def handle_continue(:set_outputs, state) do
    Outputs.set_outputs(state)
    {:noreply, state}
  end

  # Calls ----------------------------------------

  @impl true
  def handle_call({:set_motor_timed_out, timed_out}, _from, state) do
    new_state = %{state | motor_timed_out: timed_out}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
