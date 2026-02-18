import Config
config :elevator, num_floors: 4

# Import environment specific config. This ensures config/test.exs is loaded
# when MIX_ENV=test (and similarly for dev/prod).
import_config "#{Mix.env()}.exs"
