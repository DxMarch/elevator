defmodule Elevator.Application do
  use Application

  def start(_start_type, _start_args) do
    topologies = Application.fetch_env!(:libcluster, :topologies)
    driver_port = Application.fetch_env!(:elevator, :driver_port)

    children = [
      {Cluster.Supervisor, [topologies, [name: Chat.ClusterSupervisor]]},
      Elevator.Communicator,
      {Elevator.HallOrders, Elevator.num_floors()},
      Elevator.CabOrders,
      {Elevator.Driver, [{127, 0, 0, 1}, driver_port]},
      Elevator.DriverPoller,
      Elevator.FSM
    ]

    opts = [strategy: :one_for_one, name: Elevator.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
