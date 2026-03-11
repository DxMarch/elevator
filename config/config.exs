import Config
config :elevator, num_floors: 4

if config_env() == :dev do
  config :pre_commit, commands: ["format --check-formatted"], verbose: true
end
