defmodule Elevator.HallOrders.Scoring do
  @doc """
  Maybe even random numbers?
  """
  def compute_score(_hall_orders, _cab_orders) do
    :rand.uniform(10)
  end

  def merge_scores(score_map_1, score_map_2) do
    key_set = MapSet.new(Map.keys(score_map_1) ++ Map.keys(score_map_2))
    for node <- key_set do
      cond do
        Map.has_key?(score_map_1, node) and Map.has_key?(score_map_2, node) ->
          score_1 = score_map_1[node]
          score_2 = score_map_2[node]
          {node, max(score_1, score_2)}
        Map.has_key?(score_map_1, node) ->
          {node, score_map_1[node]}
        true ->
          {node, score_map_2[node]}
      end |> Enum.into(%{})
    end
  end

  def max_alive_score(score_map, alive_set) do
    alive_scores = Enum.filter(score_map, fn {node, score} -> MapSet.member?(alive_set, node) end)
    {max_node, _} = Enum.max(alive_scores, fn {node1, score1}, {node2, score2} -> 
      score1 > score2 or (score1 == score2 and node1 > node2)
    end)
    max_node
  end
end
