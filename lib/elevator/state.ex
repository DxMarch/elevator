defmodule Elevator.State do
  @moduledoc """
  Struct representing the elevator GenServer state.
  """
  alias Elevator.Types

  defstruct orders: %{}, direction: :stop, floor: :unknown, behavior: :idle

  @type t :: %__MODULE__{
          orders: Types.combined_order_map(),
          direction: Types.elev_dir(),
          floor: :unknown | Types.floor(),
          behavior: Types.elev_state()
        }
end
