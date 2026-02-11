defmodule Elevator.HallOrders do
  @moduledoc """
  Module responsible for all changes occuring to the hall_order part of the state.
  """
  use GenServer

  @type state_t :: Elevator.State.hall_order_map()

  def start_link(arg) do 
    GenServer.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec init(any()) :: {:ok, state_t()}
  def init(num_floors) do
    state = Range.new(0, num_floors - 1)
    |> Enum.flat_map(fn floor -> [{floor, :up}, {floor, :down}] end)
    |> Enum.map(&{&1, :unknown})
    |> Enum.into(%{})
    {:ok, state}
  end

  @spec receive_state(state_t()) :: :ok
  def receive_state(other_state), do: GenServer.cast(__MODULE__, {:receive_state, other_state})

  @spec button_press(non_neg_integer(), :up | :down) :: :ok
  def button_press(floor, button_type), do: GenServer.cast(__MODULE__, {:button_press, floor, button_type})

  @spec handle_cast({:receive_state, state_t()}, state_t()) :: {:noreply, state_t()}
  def handle_cast({:receive_state, _other_state}, state) do
    {:noreply, state}
  end

  @spec handle_cast({:button_press, non_neg_integer(), :up | :down}, state_t()) :: {:noreply, state_t()}
  def handle_cast({:button_press, _floor, _direction}, state) do
    {:noreply, state}
  end
end
