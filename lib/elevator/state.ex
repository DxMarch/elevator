defmodule Elevator.State do
  @moduledoc """
  Module storing the elevator GenServer state.
  """
  require Logger
  alias Elevator.Driver
  alias Elevator.Types

  defstruct direction: :stop, floor: :unknown, behavior: :idle, door_timer: nil, between_floors: true

  @type t :: %__MODULE__{
          direction: Types.elev_dir(),
          floor: :unknown | Types.floor(),
          behavior: Types.elev_state(),
          door_timer: nil | {reference(), reference()},
          between_floors: boolean()
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

  def update_floor(floor) do
    GenServer.cast(__MODULE__, {:update_floor, floor})
  end

  def get_floor() do
    GenServer.call(__MODULE__, :get_floor)
  end

  def get_between_floors() do
    GenServer.call(__MODULE__, :get_between_floors)
  end

  # Casts ----------------------------------------

  @impl true
  def handle_cast({:update_floor, floor}, state) do
    new_state = case floor do
      :between_floors ->
        %{state | between_floors: true}
      _ ->
        %{state | between_floors: false, floor: floor}
    end
    {:noreply, new_state}
  end

  # Calls ----------------------------------------
  @impl true
  def handle_call(:get_between_floors, _from, state) do
    {:reply, state.between_floors, state}
  end

  @impl true
  def handle_call(:get_floor, _from, state) do
    {:reply, state.floor, state}
  end
end
