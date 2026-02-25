# TTK4145 Elevator

## Installation
Copy environmental variables and make sure to add your IP as well as others you want to use. You can also uncomment the ones you don't want to use to stop libcluster from trying to connect to them.
```shell
cp envs/.env.example envs/.env
nano envs/.env
```

To use the IP's source them
```shell
set -a
source envs/.env
set +a
```
Or for convenience use `direnv`
```shell
# Install
sudo apt install direnv
echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
source ~/.bashrc

# Setup .envrc
cat > .envrc <<'EOF'
set -a
source envs/.env
set +a
EOF

direnv allow
```

## Run nodes
**Same computer**
```shell
# Open terminal to <path_to_repo>
iex --sname elev26@localhost -S mix
# In another terminal
iex --sname daniel@localhost -S mix
```

**Different computers**
```shell
# Computer at sanntid
iex --name elev26@$IP_ELEV26 -S mix
# Daniels computer
iex --name daniel@$IP_DANIEL -S mix
```