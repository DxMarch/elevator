defmodule Elevator.Application do
  use Application

  @default_driver_port 15_657

  def start(_start_type, _start_args) do
    topologies = Application.fetch_env!(:libcluster, :topologies)
    driver_port = get_driver_port()

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

  defp get_driver_port do
    case Integer.parse(System.get_env("DRIVER_PORT", Integer.to_string(@default_driver_port))) do
      {port, ""} -> port
      _ -> @default_driver_port
    end
  end
end
