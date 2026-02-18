defmodule Elevator.State do
  @moduledoc """
  Struct representing the elevator GenServer state.
  """
  alias Elevator.Types

  defstruct direction: :stop, floor: :unknown, behavior: :idle, door_timer: nil

  @type t :: %__MODULE__{
          direction: Types.elev_dir(),
          floor: :unknown | Types.floor(),
          behavior: Types.elev_state(),
          door_timer: nil | {reference(), reference()}
        }
end
