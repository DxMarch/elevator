defmodule Elevator.CabOrders do
  use GenServer
  @moduledoc """
  Module responsible for all changes occuring to the cab_order part of the state.
  """

  def init(arg) do
    {:ok, arg}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_orders do
    GenServer.call(__MODULE__, :get_orders)
  end

  def handle_call(:get_orders, _, state) do
    {:reply, MapSet.new([]), state}
  end
end
