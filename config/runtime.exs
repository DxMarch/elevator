import Config
import Dotenvy

env_dir_prefix = System.get_env("RELEASE_ROOT") || Path.expand("./envs")

source!([
  Path.absname(".env", env_dir_prefix),
  Path.absname("#{config_env()}.env", env_dir_prefix),
  System.get_env()
])

nodes_env = env!("NODES", :string!)
gossip_secret = env!("GOSSIP_SECRET", :string!)

nodes =
  String.split(nodes_env, [",", "\n"], trim: true)
  |> Enum.map(&String.trim/1)
  |> Enum.map(&String.to_atom/1)

config :elevator, static_nodes: nodes

topologies = [
  elevator_static: [
    strategy: Cluster.Strategy.Epmd,
    config: [
      hosts: nodes,
      timeout: 30_000,
      polling_interval: 500]
  ],
  # TODO: try multicast and broadcast at sanntid
  elevator_gossip: [
    strategy: Cluster.Strategy.Gossip,
    config: [
      broadcast_only: true, # use UDP broadcast instead of multicast
      port: 45892,
      secret: gossip_secret
    ]
  ]
]

config :libcluster, topologies: topologies
