# TTK4145 Elevator

### LOC stats (Elixir)
**Lib:** <!-- LIB_COUNT -->997<!-- END_LIB_COUNT -->\
**Test:** <!-- TEST_COUNT -->540<!-- END_TEST_COUNT -->


## Running nodes

Copy `.env.example` to `.env` and fill in the values, then:

```bash
# Local dev — run in separate terminals
./scripts/start.sh --local 1
./scripts/start.sh --local 2

# Local dev — override simulator port per node
./scripts/start.sh --local 1 --port 15657
./scripts/start.sh --local 2 --port 15658

# Cluster — uses ELEVATOR_ID set by sync.sh in .bashrc
./scripts/start.sh

# Cluster — explicit ID override
./scripts/start.sh 1

# Cluster — explicit ID + simulator port override
./scripts/start.sh 1 --port 15658
```

### Sim

The simulator supports the following options:
- `--port` — TCP port used to connect to the simulator (default: 15657). Change this to avoid conflicts; you can run multiple simulators on one machine by using different ports.
- `--numfloors` — Number of floors (2–9; default: 4).

Options passed on the command line (for example, `./SimElevatorServer --port 12345`) override settings in `simulator.con`, which in turn override the program defaults. Place `simulator.con` in the same folder as the executable. Options are case-insensitive.

Default keyboard controls
- Up: qwertyui
- Down: sdfghjkl
- Cab: zxcvbnm,.
- Stop: p
- Obstruction: -
- Motor manual override: Down: 7, Stop: 8, Up: 9
- Move elevator back in bounds (away from the end-stop switches): 0

Up, Down, Cab and Stop buttons can be toggled (and held) using uppercase letters.

Run the simulator:
```bash
./server/SimElevatorServer
```

## Deploying to remotes

### Setup

```bash
cp scripts/.env.example scripts/.env
# Edit scripts/.env with SSHPASS and SYNC_DEST

# Edit scripts/hosts with elevator ID → user@host mappings
```

### Sync files

```bash
# Sync to all configured elevators
./scripts/sync.sh --all

# Sync specific elevator IDs only
./scripts/sync.sh 25 26

# On each host after first sync:
./scripts/install.sh
```

### Remote shells

```bash
# Open a tmux session with one pane per configured host
./scripts/open_remotes.sh --all

# Or open only selected elevators
./scripts/open_remotes.sh 25 26
```

Running `open_remotes.sh` again recreates the local tmux layout, while each
remote pane re-attaches to the same remote `elevator` tmux session.

## Packetloss
To simulate packetloss run
```shell
sudo ./scripts/packetloss.sh <percentage> -ie
```
- `-i` is incomming traffic
- `-o`is outgoing
- `-e`is Elixir/Erlang and autodetects Beam ports
