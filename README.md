# XEQM Labs — Service Node Installer

Easy setup and management of XEQM service nodes on a single Linux server.

---

## Get the scripts (run as root)

> The scripts must be run as root. They automatically create separate users to run each service node — you do not need to manage this yourself.

```bash
cd ~
sudo apt -y install git
git clone https://github.com/vellitas/eqsnode-installer-script
cd eqsnode-installer-script
```

**Already cloned before? Pull the latest:**

```bash
cd ~/eqsnode-installer-script
git pull --force
```

---

## Install a single service node

```bash
bash install.sh --open-firewall
```

`--open-firewall` automatically configures UFW or iptables to open all required ports. It is recommended for most setups.

**Preview what the installer will do before running it:**

```bash
bash install.sh -i
```

---

## Install multiple service nodes (one server)

```bash
bash install.sh --nodes 2 --open-firewall
```

> Tip: use `--one-passwd-file` (see Advanced section) to avoid typing passwords for each user.

---

## Blockchain seeding options

When installing, you will be asked how to seed the blockchain. You can also pass it directly:

| Option | Description |
|---|---|
| `--copy-blockchain bootstrap` | Download bootstrap from XEQM Labs (~15 min) — **recommended** |
| `--copy-blockchain auto` | Copy from an existing node on this server |
| `--copy-blockchain /home/snode/.equilibria` | Copy from a specific path |
| `--copy-blockchain no` | Sync fresh from the network (many hours) |
| `--copy-blockchain no,auto` | First node syncs fresh, remaining nodes copy from it |

```bash
bash install.sh --nodes 2 --copy-blockchain bootstrap --open-firewall
```

---

## Quiet / non-interactive mode

Pass all options up front and the installer will run without asking any questions:

```bash
bash install.sh --nodes 2 --copy-blockchain bootstrap --open-firewall --quiet
```

In quiet mode, blockchain defaults to `bootstrap` if `--copy-blockchain` is not specified.

---

## Upgrading service nodes

Upgrade nodes running as users `snode` and `snode2` to the latest release:

```bash
bash upgrade.sh --user snode,snode2
```

With firewall and log level options:

```bash
bash upgrade.sh --user snode,snode2 --open-firewall --set-daemon-log-level 0,stacktrace:FATAL
```

---

## Health check and diagnostics (doctor.sh)

Scan all running nodes for problems and get a remediation plan:

```bash
bash doctor.sh
```

Auto-fix corrupt or stuck blockchains (copies from a healthy donor node or downloads bootstrap):

```bash
bash doctor.sh --auto-fix
```

---

## Key transfer (transfer.sh)

Move a service node identity between users or servers without losing registration.

**List all nodes and their public keys:**

```bash
bash transfer.sh --list
```

**Export a node's key to a portable archive (for moving to another server):**

```bash
bash transfer.sh --export --user snode1 --output-dir /tmp
```

**Import the key on the destination server:**

```bash
bash transfer.sh --import --user snode2 --key-file /tmp/xeqm-key-snode1-20260513120000.tar.gz
```

**Transfer a key between two users on the same server:**

```bash
bash transfer.sh --transfer --from snode1 --to snode3
```

---

## Firewall ports

If you manage your own firewall (OPNsense, pfSense, cloud security groups, etc.), open these ports for each node:

| Purpose | Default Port | Direction |
|---|---|---|
| P2P | 9230 | Inbound + Outbound |
| Quorumnet (SN consensus) | 9232 | Inbound + Outbound |
| OxenMQ | 9233 | Inbound + Outbound |

For each additional node, add 100 to each port (node 2: 9330 / 9332 / 9333, etc.).

---

## Advanced features

### Custom username

```bash
bash install.sh --user mysnode10
```

### Multi-node with specific usernames and ports

```bash
bash install.sh --nodes 2 --user mysnode1,mysnode2 --ports p2p:9330+9430,rpc:9331+9431
```

Shorthand:

```bash
bash install.sh -n 2 -u mysnode1,mysnode2 -p p2p:9330+9430,rpc:9331+9431
```

### Install a specific version

```bash
bash install.sh --nodes 2 --version v20.1.1
```

```bash
bash install.sh --nodes 2 --version 122d5f6a6
```

Omitting `--version` installs the latest official release.

### Set daemon log level

```bash
bash install.sh --nodes 2 --set-daemon-log-level 0,stacktrace:FATAL
```

### Shared password file (avoid repeated password prompts)

Generate the password file once before installing:

```bash
bash install.sh --one-passwd-file
```

All subsequent installs will use this file — no password prompts. To go back to manual passwords, remove it:

```bash
rm ~/eqsnode-installer-script/.onepasswd
```

---

## Built-in help

```bash
bash install.sh --help
bash upgrade.sh --help
bash doctor.sh --help
bash transfer.sh --help
```

---

For a full walkthrough written for non-technical users, see [USER_GUIDE.md](USER_GUIDE.md).
