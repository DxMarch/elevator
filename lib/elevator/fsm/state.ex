defmodule Elevator.FSM.State do
  @moduledoc """
  GenServer holding the physical state of the elevator.

  Acts as the single source of truth for what the elevator *is* right now -
  its floor, direction, behavior, and fault conditions. 
  """

  defstruct behavior: :idle,
            between_floors: false,
            direction: :down,
            door_open_time: Time.utc_now(),
            floor: :unknown,
            last_floor_time: Time.utc_now(),
            motor_timed_out: false,
            obstructed: false

  @type elev_behavior :: :moving | :idle | :door_open

  @type t :: %__MODULE__{
          direction: :up | :down,
          behavior: elev_behavior(),
          floor: :unknown | Elevator.floor(),
          between_floors: boolean(),
          obstructed: boolean(),
          motor_timed_out: boolean(),
          door_open_time: Time.t(),
          last_floor_time: Time.t()
        }

  use GenServer

  @impl true
  def init(_arg) do
    state = %__MODULE__{}
    {:ok, state}
  end

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  # User API --------------------------------------------------

  @doc """
  Updates floor and between_floors status.
  """
  @spec set_floor(:between_floors | Elevator.floor()) :: :ok
  def set_floor(floor), do: GenServer.cast(__MODULE__, {:set_floor, floor})

  @doc """
  Sets obstructed to true if door is open and obstruction switch is on.
  Otherwise, obstructed is set to false.
  """
  @spec set_obstruction(boolean()) :: :ok
  def set_obstruction(obstruction_switch),
    do: GenServer.cast(__MODULE__, {:set_obstruction, obstruction_switch})

  @spec set_direction(:up | :down) :: :ok
  def set_direction(dir), do: GenServer.cast(__MODULE__, {:set_direction, dir})

  @spec set_behavior(elev_behavior()) :: :ok
  def set_behavior(behavior), do: GenServer.cast(__MODULE__, {:set_behavior, behavior})

  @doc """
  Opens the door if the elevator is at a floor.
  Does nothing if the elevator is between floors.
  """
  @spec open_door() :: :ok
  def open_door(), do: GenServer.cast(__MODULE__, :open_door)

  @spec set_motor_timed_out(boolean()) :: :ok
  def set_motor_timed_out(timed_out),
    do: GenServer.cast(__MODULE__, {:set_motor_timed_out, timed_out})

  @spec get_state() :: t()
  def get_state(), do: GenServer.call(__MODULE__, :get_state)

  @spec operational?() :: boolean()
  def operational?(), do: GenServer.call(__MODULE__, :operational?)

  # Casts --------------------------------------------------

  @impl true
  def handle_cast({:set_floor, new_floor}, state) do
    new_state =
      case new_floor do
        :between_floors ->
          %{state | between_floors: true}

        floor ->
          %{state | between_floors: false, floor: floor}
      end
      |> detect_and_update_last_floor_time(state)

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
    new_state =
      %{state | behavior: behavior}
      |> detect_and_update_last_floor_time(state)

    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:open_door, state) do
    new_state =
      if state.between_floors do
        state
      else
        %{state | behavior: :door_open, door_open_time: Time.utc_now()}
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_motor_timed_out, timed_out}, state) do
    new_state = %{state | motor_timed_out: timed_out}
    {:noreply, new_state}
  end

  # Calls --------------------------------------------------

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call(:operational?, _from, state) do
    {:reply, not (state.motor_timed_out or state.obstructed), state}
  end

  @spec detect_and_update_last_floor_time(t(), t()) :: t()
  defp detect_and_update_last_floor_time(new_state, old_state) do
    if old_state.between_floors != new_state.between_floors or
         (old_state.behavior != :moving and new_state.behavior == :moving) do
      %{new_state | last_floor_time: Time.utc_now()}
    else
      new_state
    end
  end
end
