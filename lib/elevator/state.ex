defmodule Elevator.State do
  @moduledoc """
  Module storing the elevator GenServer state.
  """
  require Logger
  alias Elevator.Driver
  alias Elevator.Types

  defstruct direction: :stop, behavior: :idle, floor: :unknown, between_floors: true, door_open_time: Time.utc_now() 

  @type t :: %__MODULE__{
          direction: Types.elev_dir(),
          behavior: Types.elev_state(),
          floor: :unknown | Types.floor(),
          between_floors: boolean(),
          door_open_time: Time.t()
        }

  use GenServer

  @impl true
  def init(_arg) do
    floor = Driver.get_floor_sensor_state()
    state = %Elevator.State{}

    state =
      if floor == :between_floors do
        Driver.set_motor_direction(:down)
        Logger.debug("Initialized between floors, going down")
        %{state | direction: :down, behavior: :moving, between_floors: true}
      else
        %{state | floor: floor, between_floors: false}
      end

    {:ok, state}
  end

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def set_floor(floor) do
    GenServer.cast(__MODULE__, {:set_floor, floor})
  end

  def set_direction(dir) do
    GenServer.cast(__MODULE__, {:set_direction, dir})
  end

  def set_behavior(behavior) do
    GenServer.cast(__MODULE__, {:set_behavior, behavior})
  end

  def set_door_open_time(door_open_time) do
    GenServer.cast(__MODULE__, {:set_door_open_time, door_open_time})
  end

  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  # Casts ----------------------------------------
  @impl true
  def handle_cast({:set_floor, floor}, state) do
    new_state = case floor do
      :between_floors ->
        %{state | between_floors: true}
      _ ->
        %{state | between_floors: false, floor: floor}
    end
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:set_direction, dir}, state) do
    {:noreply, %{state | direction: dir}}
  end

  @impl true
  def handle_cast({:set_behavior, behavior}, state) do
    {:noreply, %{state | behavior: behavior}}
  end

  def handle_cast({:set_door_open_time, door_open_time}, state) do
    {:noreply, %{state | door_open_time: door_open_time}}
  end


  # Calls ----------------------------------------
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end
