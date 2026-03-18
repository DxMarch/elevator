import Config
import Dotenvy

# Load .env file, then fall back to actual environment variables.
# The path can be overridden with the ENV_FILE env var.
env_file = System.get_env("ENV_FILE", ".env")
source!([env_file, System.get_env()])

driver_port =
  case Integer.parse(System.get_env("DRIVER_PORT", "15657")) do
    {port, ""} -> port
    _ -> 15_657
  end

gossip_secret = env!("GOSSIP_SECRET", :string, "change_me_in_dotenv")

config :elevator, driver_port: driver_port

config :libcluster,
  topologies: [
    elevator: [
      strategy: Cluster.Strategy.Gossip,
      config: [secret: gossip_secret]
    ]
  ]
