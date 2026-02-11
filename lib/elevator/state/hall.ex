defmodule Elevator.State.Hall do
  @type t :: 
    :unknown 
    | :idle 
    | {state :: :pending, barrier_set :: MapSet.t()} 
    | {state :: :confirmed, score_map :: map(), barrier_set :: MapSet.t()}
end
