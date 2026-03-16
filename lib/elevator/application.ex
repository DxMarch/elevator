defmodule Elevator.Application do
  use Application

  def start(_start_type, _start_args) do
    topologies = Application.fetch_env!(:libcluster, :topologies)
    driver_port = Application.fetch_env!(:elevator, :driver_port)

    children = [
      {Cluster.Supervisor, [topologies, [name: Elevator.ClusterSupervisor]]},
      Elevator.Communicator,
      {Elevator.HallOrders, Elevator.num_floors()},
      Elevator.CabOrders,
      {Elevator.Hardware.Driver, [{127, 0, 0, 1}, driver_port]},
      Elevator.FSM.State,
      Elevator.FSM.Action,
      Elevator.Hardware.InputPoller
    ]

    opts = [strategy: :rest_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
