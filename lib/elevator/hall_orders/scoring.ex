defmodule Elevator.HallOrders.Scoring do
  alias Elevator.Decision
  alias Elevator.CabOrders
  require Logger

  @doc """
  Maybe even random numbers?
  """
  def compute_score({floor, btn_dir}, my_hall_orders) do
    state = Elevator.FSM.State.get_state()
    cab_orders = CabOrders.get_my_orders()
    behavior_str = [idle: "idle", moving: "moving", door_open: "doorOpen"][state.behavior]

    elev_state = %{
      state: %{
        state: behavior_str,
        floor: state.floor,
        direction: state.direction,
        cabRequests:
          Enum.map(0..Elevator.num_floors(), fn floor -> MapSet.member?(cab_orders, floor) end)
      },
      hallRequests:
        Enum.map(
          0..Elevator.num_floors(),
          fn floor ->
            [
              MapSet.member?(Map.get(my_hall_orders, floor, MapSet.new()), :hall_up),
              MapSet.member?(Map.get(my_hall_orders, floor, MapSet.new()), :hall_down)
            ]
          end
        ),
      newOrder: %{floor: floor, direction: [hall_up: :up, hall_down: :down][btn_dir]}
    }

    json_input = JSON.encode!(elev_state)

    try do
      {output, 0} = System.cmd(Elevator.time_to_serve_executable(), ["-i", json_input])
      String.to_integer(String.trim(output))
    rescue
      _ ->
        30000
    end
  end

  def merge_scores(score_map_1, score_map_2) do
    MapSet.new(Map.keys(score_map_1) ++ Map.keys(score_map_2))
    |> Enum.map(fn node ->
      cond do
        Map.has_key?(score_map_1, node) and Map.has_key?(score_map_2, node) ->
          score_1 = score_map_1[node]
          score_2 = score_map_2[node]
          {node, max(score_1, score_2)}

        Map.has_key?(score_map_1, node) ->
          {node, score_map_1[node]}

        true ->
          {node, score_map_2[node]}
      end
    end)
    |> Enum.into(%{})
  end

  def max_alive_score(score_map, alive_set) do
    alive_scores = Enum.filter(score_map, fn {node, _} -> MapSet.member?(alive_set, node) end)

    {max_node, _} =
      Enum.min(alive_scores, fn {node1, score1}, {node2, score2} ->
        score1 < score2 or (score1 == score2 and node1 < node2)
      end)

    max_node
  end
end
