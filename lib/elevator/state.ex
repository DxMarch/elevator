defmodule Elevator.State do
  @moduledoc """
  Struct representing the elevator GenServer state.
  """

  @enforce_keys [:direction, :floor, :behavior]
  defstruct [:direction, :floor, :behavior]

  @type t :: %__MODULE__{
    direction: Elevator.Types.elev_dir(),
    floor: :unknown | Elevator.Types.floor(),
    behavior: Elevator.Types.elev_state(),
  }
end
