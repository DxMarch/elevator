defmodule Elevator.Application do
  @moduledoc """
  Main entry point, starting the supervisor.
  Supervisor children ordering is somewhat based on abstraction level: 
  modules "closer" to hardware are started last because they are more likely to crash.
  Combined with the rest_for_one strategy, this lets us keep high level state when a lower level module crashes.
  """
  use Application

  @spec start(Application.start_type(), term()) :: {:ok, pid()} | {:error, term()}
  def start(_start_type, _start_args) do
    topologies = Application.fetch_env!(:libcluster, :topologies)
    driver_port = Application.fetch_env!(:elevator, :driver_port)

    children = [
      {Cluster.Supervisor, [topologies, [name: Elevator.ClusterSupervisor]]},
      Elevator.Communicator,
      {Elevator.HallOrders, Elevator.num_floors()},
      Elevator.CabOrders,
      Elevator.FSM.State,
      Elevator.FSM.Transition,
      {Elevator.Hardware.Driver, [{127, 0, 0, 1}, driver_port]},
      Elevator.Hardware.InputPoller
    ]

    opts = [strategy: :rest_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
