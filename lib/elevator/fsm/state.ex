defmodule Elevator.FSM.State do
  @moduledoc """
  GenServer holding the physical state of the elevator.

  Acts as the single source of truth for what the elevator *is* right now -
  its floor, direction, behavior, and fault conditions. 
  """
  require Logger
  alias Elevator.Types

  defstruct direction: :down,
            behavior: :moving,
            floor: :unknown,
            between_floors: true,
            obstructed: false,
            motor_timed_out: false,
            door_open_time_ms: Time.utc_now(),
            last_floor_time: Time.utc_now()

  @type t :: %__MODULE__{
          direction: Types.elev_dir(),
          behavior: Types.elev_behavior(),
          floor: :unknown | Types.floor(),
          between_floors: boolean(),
          obstructed: boolean(),
          motor_timed_out: boolean(),
          door_open_time_ms: Time.t(),
          last_floor_time: Time.t()
        }

  use GenServer

  @impl true
  def init(_arg) do
    state = %Elevator.FSM.State{}
    {:ok, state}
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # User API ----------------------------------------

  def set_floor(floor), do: GenServer.cast(__MODULE__, {:set_floor, floor})

  def set_obstruction(obstructed), do: GenServer.cast(__MODULE__, {:set_obstruction, obstructed})

  def set_direction(dir), do: GenServer.cast(__MODULE__, {:set_direction, dir})

  def set_behavior(behavior), do: GenServer.cast(__MODULE__, {:set_behavior, behavior})

  @doc """
  Opens the door if the elevator is at a floor.
  Does nothing if the elevator is between floors.
  """
  def open_door(), do: GenServer.cast(__MODULE__, :open_door)

  def set_motor_timed_out(timed_out),
    do: GenServer.cast(__MODULE__, {:set_motor_timed_out, timed_out})

  def get_state(), do: GenServer.call(__MODULE__, :get_state)

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

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_obstruction, obstruction_switch}, state) do
    obstructed = obstruction_switch and state.behavior == :door_open
    {:noreply, %{state | obstructed: obstructed}}
  end

  @impl true
  def handle_cast({:set_direction, dir}, state) do
    {:noreply, %{state | direction: dir}}
  end

  @impl true
  def handle_cast({:set_behavior, behavior}, state) do
    {:noreply, %{state | behavior: behavior}}
  end

  @impl true
  def handle_cast(:open_door, state) do
    new_state =
      if state.between_floors do
        state
      else
        %{state | behavior: :door_open, door_open_time_ms: Time.utc_now()}
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_motor_timed_out, timed_out}, state) do
    new_state = %{state | motor_timed_out: timed_out}
    {:noreply, new_state}
  end

  # Calls ----------------------------------------

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
