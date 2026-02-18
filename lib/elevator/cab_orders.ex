defmodule Elevator.CabOrders do
  use GenServer
  @moduledoc """
  Module responsible for all changes occuring to the cab_order part of the state.
  """
  alias Elevator.Types

  # Send cab orders when asked
  def handle_call(:get, _, state) do
    {:reply, state, state}
  end

  @spec handle_cast({:update, Types.cab_order_map()}, Types.cab_order_map()) :: {:noreply, Types.cab_order_map()}
  def handle_cast({:update, order_map}, state) do
    # Update the state with new orders if a higher version is received

    new_state = Enum.reduce(order_map, state, fn({node_id, received}, acc) ->
      current = Map.get(state, node_id, %{version: 0, orders: MapSet.new()})

      if received.version > current.version do
        Map.put(acc, node_id, received)
      else
        acc
      end
    end)


    {:noreply, new_state}
  end


end
