defmodule Elevator.Communicator do
  @moduledoc """
  Module responsible for all communication with other elevators.
  """
  # TODO: Implement

  def who_is_alive do
    MapSet.new([Node.self()] ++ Node.list(:connected))
  end
end
