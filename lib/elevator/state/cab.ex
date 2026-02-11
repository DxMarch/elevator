defmodule Elevator.State.Cab do
  # TODO: Decide cab order format
  defstruct [:version, :orders]

  @type t :: %__MODULE__{
    version: non_neg_integer(),
    orders: list()
  }
end
