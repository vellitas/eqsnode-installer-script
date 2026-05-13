# XEQM Labs — Service Node User Guide

Welcome! This guide will walk you through everything you need to run an XEQM service node —
from first installation to day-to-day management. No deep technical knowledge required.
Take it one step at a time and you'll be up and running in under an hour.

---

## Table of Contents

1. [What Is a Service Node?](#1-what-is-a-service-node)
2. [What You Need Before You Start](#2-what-you-need-before-you-start)
3. [Getting the Scripts](#3-getting-the-scripts)
4. [Installing Your First Node](#4-installing-your-first-node)
5. [Installing Multiple Nodes on One Server](#5-installing-multiple-nodes-on-one-server)
6. [Completing Setup — Staking Your Node](#6-completing-setup--staking-your-node)
7. [Daily Node Management](#7-daily-node-management)
8. [Upgrading Your Nodes](#8-upgrading-your-nodes)
9. [Health Checks and Auto-Repair](#9-health-checks-and-auto-repair)
10. [Moving a Node to Another Server](#10-moving-a-node-to-another-server)
11. [Firewall Configuration](#11-firewall-configuration)
12. [Quiet Mode (Unattended Installs)](#12-quiet-mode-unattended-installs)
13. [Quick Reference Card](#13-quick-reference-card)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. What Is a Service Node?

A service node is a computer (usually a rented server) that helps run the XEQM network.
Think of it like volunteering a server to keep the network healthy. In return, the owner
earns XEQM rewards.

To activate a node you must **stake** — temporarily lock up a set amount of XEQM as a
guarantee that your node will behave correctly. Your staked XEQM is never spent; it is
returned when you stop operating the node.

These scripts handle all the technical work of setting up and managing your node. Your
job is to answer a few questions during installation, then stake from your wallet.

---

## 2. What You Need Before You Start

### Server Requirements

| Requirement | Minimum | Recommended |
|---|---|---|
| Operating System | Ubuntu 20.04 or 22.04 | Ubuntu 22.04 LTS |
| RAM | 2 GB | 4 GB |
| Disk Space | 50 GB free | 100 GB+ SSD |
| Network | Stable broadband | Dedicated connection |

> **Each additional node** on the same server needs roughly **1.3 GB more RAM** and
> **38 GB more disk space**.

### Ports That Must Be Open

Your server's firewall (or router if you use one) must allow traffic on these ports
for **each node**:

| Port | Purpose |
|---|---|
| **9230** | Peer-to-peer — how your node finds others |
| **9232** | Quorumnet — service node consensus |
| **9233** | OxenMQ — public messaging |

If you are on a VPS (rented cloud server), these ports are usually easy to open in your
provider's control panel. If you run your own hardware behind a router, you will need
to set up port forwarding. See [Section 11](#11-firewall-configuration) for details.

### Things to Have Ready

- SSH access to your server (or be sitting at it)
- Your XEQM wallet, for staking after installation
- About 30–60 minutes of time

---

## 3. Getting the Scripts

Log in to your server and run the following commands. Copy and paste them exactly.

```bash
# Download the scripts
git clone https://github.com/misterr-labs/eqsnode-installer-script.git

# Move into the folder
cd eqsnode-installer-script
```

You only need to do this once. For future upgrades the scripts handle themselves.

---

## 4. Installing Your First Node

### Step 1 — Run the installer

From inside the `eqsnode-installer-script` folder, run:

```bash
bash install.sh
```

The installer will display a welcome screen, then guide you through a series of choices.

---

### Step 2 — Choose how to get the blockchain

The blockchain is the complete history of all XEQM transactions. Your node needs a full
copy before it can participate in the network.

You will see a menu like this:

```
How should this node get its blockchain?

  [1] Download bootstrap  (fastest, ~15 min  —  https://bootstrap.xeqmlabs.com)
  [2] Copy from an existing active node on this server  (auto-detect)
  [3] Sync from the network  (slowest, may take many hours)

  Choice [1]:
```

**What to choose:**

| Option | When to use it |
|---|---|
| **1 — Bootstrap** | First node on a new server. Fast, ~15 minutes. |
| **2 — Copy from existing node** | You already have a node running on this server. |
| **3 — Sync from network** | Only if bootstrap is unavailable and no existing node. |

For almost everyone, **press Enter to accept option 1**.

---

### Step 3 — Wait for the installer to finish

The installer will:

1. Install required system packages
2. Download the XEQM software
3. Set up a dedicated user account for your node
4. Create a system service (so the node restarts automatically after reboots)
5. Start the node and download the blockchain

You will see progress on screen. The blockchain download takes about 15 minutes
with the bootstrap option.

---

### Step 4 — Note the final instructions

When installation finishes, the screen will show:

- The command to **stake your node** (complete in Step 6 below)
- The **firewall ports** you need to open

Write these down or scroll back to them when needed.

---

## 5. Installing Multiple Nodes on One Server

You can run several nodes on one server as long as it has enough RAM and disk space
(roughly 2 GB RAM and 50 GB disk per node).

### Install 2 nodes at once

```bash
bash install.sh --nodes 2
```

### Install 3 nodes with usernames you choose

```bash
bash install.sh --nodes 3 --user snode1,snode2,snode3
```

### Install 2 nodes, first downloads bootstrap, second copies from first

```bash
bash install.sh --nodes 2 --copy-blockchain no,auto
```

> **Tip:** Using `no,auto` is the fastest way to install multiple nodes — only the
> first node downloads the bootstrap, and the rest copy from it in minutes.

### What happens with ports?

Each node automatically gets its own set of ports. With default settings:

| Node | P2P | RPC | Quorumnet | OxenMQ |
|---|---|---|---|---|
| Node 1 | 9230 | 9231 | 9232 | 9233 |
| Node 2 | 9330 | 9331 | 9332 | 9333 |
| Node 3 | 9430 | 9431 | 9432 | 9433 |

Remember to open ports **9230, 9232, 9233** (and the next hundred for each extra node)
in your firewall.

---

## 6. Completing Setup — Staking Your Node

Installation sets up the software, but your node is **not active on the network yet**.
You need to register it by staking XEQM from your wallet.

### Step 1 — Run the prepare command

Replace `snode1` with your node's username (shown at the end of installation):

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh prepare_sn'
```

This command will display staking instructions including:

- The **amount of XEQM** required to stake
- The **address** to send it to
- Step-by-step instructions for your wallet

### Step 2 — Follow the on-screen instructions

Read the output carefully. It will tell you exactly what to do in your XEQM wallet
to complete registration.

### Step 3 — Confirm your node is registered

After staking, wait a few minutes then check your node's status:

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_status'
```

When registration is confirmed you will see your node listed as active.

> **Important:** Your node must be fully synced with the network before staking.
> Run `bash xeqm-node.sh status` to confirm the block height matches the network.

---

## 7. Daily Node Management

All management commands follow this pattern — replace `snode1` with your node's username:

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh COMMAND'
```

### Check if your node is running

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh status'
```

You will see something like:

```
Height: 1234567/1234567 (100.0%) on mainnet, not mining, net hash ...
```

The number before the `/` is your node's current block. The number after is the
network's latest block. When they match (100%), your node is fully synced.

---

### Start your node

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'
```

> Nodes start automatically when the server boots. You only need this command
> if you manually stopped the node or after a crash.

---

### Stop your node

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop'
```

> **Warning:** Stopping a registered node means it won't earn rewards while stopped.
> If stopped for too long the network may deregister it.

---

### View live logs

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh log'
```

This shows a live stream of what your node is doing. Press **Ctrl+C** to stop watching.

---

### Get your node's public key

Your public key is your node's unique identity on the network. You may need it for
staking pools or to verify your node is registered.

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_key'
```

---

### Check network registration status

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_status'
```

---

### Managing multiple nodes

If you have several nodes, repeat the command for each username:

```bash
# Node 1
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh status'

# Node 2
sudo -H -u snode2 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh status'
```

Or use [doctor.sh](#9-health-checks-and-auto-repair) to check all nodes at once.

---

## 8. Upgrading Your Nodes

When a new XEQM version is released, run the upgrade script. It automatically
backs up your node keys before making any changes.

### Upgrade one node

```bash
bash upgrade.sh --user snode1
```

### Upgrade multiple nodes at once

```bash
bash upgrade.sh --user snode1,snode2,snode3
```

The first node downloads and compiles the new software. The rest copy from it,
so the process is much faster for node 2, 3, etc.

### Upgrade to a specific version

```bash
bash upgrade.sh --user snode1 --version v20.1.0
```

> **Before upgrading:** Check the XEQM community channels for any special upgrade
> instructions for the new version. Some releases require additional steps.

---

## 9. Health Checks and Auto-Repair

The `doctor.sh` script checks all your nodes at once and can fix common problems
automatically.

### Run a health check

```bash
bash doctor.sh
```

The doctor will check every active node on your server and report on:

| Check | What It Means |
|---|---|
| ✅ NTP synchronized | Your server clock is accurate (required for consensus) |
| ✅ Disk space | Enough space for the blockchain to grow |
| ✅ Service active | The node's system service is running |
| ✅ Public key readable | The node can identify itself on the network |
| ✅ Blockchain healthy | Your node's blockchain matches the network |

---

### What the results mean

**HEALTHY** — Your node is working correctly. Nothing to do.

**SYNCING** — Your node is downloading the blockchain. This is normal after a fresh
install or restart. Wait for it to reach 100%.

**CORRUPT / STUCK** — Your node's blockchain data is damaged or frozen. The doctor
will offer to fix it automatically.

---

### Auto-repair

If a problem is found, the doctor will offer to fix it:

```
Corrupt/stuck blockchains found. Auto-fix from healthy donor? [Y/N]:
```

**If you have another healthy node on the same server:** Type `Y` and press Enter.
The doctor copies the good blockchain to the broken node — takes a few minutes.

**If you have no other healthy nodes on this server:**

```
How would you like to fix the corrupt node(s)?

  [1] Download bootstrap from https://bootstrap.xeqmlabs.com  (~15 min)
  [2] Skip — I will fix manually later
```

Choose **1** to download a fresh blockchain automatically.

---

### Auto-fix without prompts

If you want the doctor to fix everything without asking questions:

```bash
bash doctor.sh --auto-fix
```

---

### Remediation plan

When the doctor finds problems it can't fix automatically, it prints a
**Remediation Plan** — a numbered list of commands you can run yourself to resolve
each issue. Copy and paste them one at a time.

---

## 10. Moving a Node to Another Server

If you need to move a service node to a new server — for maintenance, to switch from
Docker to bare metal, or to consolidate servers — use `transfer.sh`.

> **Why does moving matter?** Your node has a unique key that identifies it on the
> network. Moving the key means the new server takes over as that node, keeping your
> stake and registration intact.

### See all your nodes and their keys

```bash
bash transfer.sh --list
```

Output:

```
  User             Public Key
  ────────────────  ────────────────────────────────────────────────────────────────
  snode1           abcdef1234567890...
  snode2           fedcba0987654321...
```

---

### Step 1 — Export the key from the old server

Run this on your **old server**:

```bash
bash transfer.sh --export --user snode1
```

This creates a file like `xeqm-key-snode1-20260513120000.tar.gz` in your current
folder. This file **is your node's identity** — keep it safe.

> **Warning:** Anyone with this file can take over your service node. Do not share it
> or store it in a public location.

---

### Step 2 — Copy the file to the new server

Use your preferred method to copy the archive file to the new server.

One common way (run from your local computer):

```bash
scp xeqm-key-snode1-20260513120000.tar.gz youruser@new-server-ip:/home/youruser/
```

---

### Step 3 — Install a fresh node on the new server

On the **new server**, run the installer as normal (see [Section 4](#4-installing-your-first-node)).
The new node will get a fresh key — you will replace it in the next step.

---

### Step 4 — Import the key on the new server

On the **new server**, run:

```bash
bash transfer.sh --import --user snode1 --key-file xeqm-key-snode1-20260513120000.tar.gz
```

The script will:
1. Stop the node
2. Back up the temporary key
3. Install your original key
4. Restart the node

Your node is now running on the new server with its original identity.

---

### Moving a key between users on the same server

```bash
bash transfer.sh --transfer --from snode1 --to snode2
```

---

## 11. Firewall Configuration

### Automatic configuration (UFW or iptables)

If you use Ubuntu's built-in firewall (UFW) or iptables, the installer can configure
it for you automatically. Add `--open-firewall` when running the installer:

```bash
bash install.sh --open-firewall
```

The installer detects which firewall you have and opens the correct ports.

---

### Manual configuration (OPNSense, pfSense, or hardware firewalls)

If you manage your own firewall, the installer will print the ports you need to open
at the end of installation. For reference, here they are:

**For each service node**, allow **inbound TCP** on:

| Service | Port | Notes |
|---|---|---|
| P2P | 9230 | Required — peer discovery |
| Quorumnet | 9232 | Required — service node consensus |
| OxenMQ | 9233 | Required — public messaging |

For a second node on the same server, add 100 to each port (9330, 9332, 9333).
For a third node, add 200 (9430, 9432, 9433), and so on.

> **Do not open port 9231 (RPC) publicly.** This port is for internal use only
> and should remain closed to the internet.

---

### After changing firewall rules

After opening ports, verify your node is reachable using an online port checker or
by asking in the XEQM community. A node that is not reachable on its P2P, Quorumnet,
and OxenMQ ports will not earn rewards and may be deregistered.

---

## 12. Quiet Mode (Unattended Installs)

If you are comfortable with the command line and want to install without answering
any questions, use `--quiet` combined with all required options.

The installer will use defaults or the options you provide, and will not pause to ask
anything.

### Example: fully unattended install

```bash
bash install.sh \
  --quiet \
  --nodes 1 \
  --user snode1 \
  --copy-blockchain bootstrap \
  --open-firewall
```

### Example: unattended multi-node install

```bash
bash install.sh \
  --quiet \
  --nodes 2 \
  --user snode1,snode2 \
  --copy-blockchain no,auto \
  --open-firewall
```

### Example: unattended upgrade

```bash
bash upgrade.sh --user snode1,snode2
```

> **Quiet mode defaults:** When `--copy-blockchain` is not specified in quiet mode,
> the installer uses `bootstrap` automatically.

---

## 13. Quick Reference Card

### Installation

| Goal | Command |
|---|---|
| Install one node | `bash install.sh` |
| Install with bootstrap | `bash install.sh --copy-blockchain bootstrap` |
| Install 3 nodes | `bash install.sh --nodes 3` |
| Preview settings before install | `bash install.sh --inspect-auto-magic` |
| Set a shared password for all node users | `bash install.sh --one-passwd-file` |

### Node Management (replace `snode1` with your username)

| Goal | Command |
|---|---|
| Check sync status | `sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh status'` |
| Start node | `sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'` |
| Stop node | `sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh stop'` |
| View live logs | `sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh log'` |
| Stake / register node | `sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh prepare_sn'` |
| Show public key | `sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_key'` |
| Check registration status | `sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh print_sn_status'` |

### Health & Repair

| Goal | Command |
|---|---|
| Check all nodes | `bash doctor.sh` |
| Check and auto-fix without prompts | `bash doctor.sh --auto-fix` |

### Upgrade

| Goal | Command |
|---|---|
| Upgrade one node | `bash upgrade.sh --user snode1` |
| Upgrade multiple nodes | `bash upgrade.sh --user snode1,snode2` |

### Key Transfer

| Goal | Command |
|---|---|
| List all nodes and keys | `bash transfer.sh --list` |
| Export a node key | `bash transfer.sh --export --user snode1` |
| Import a node key | `bash transfer.sh --import --user snode1 --key-file xeqm-key-snode1-*.tar.gz` |
| Move key between users (same server) | `bash transfer.sh --transfer --from snode1 --to snode2` |

---

## 14. Troubleshooting

### "My node shows 0/0 for block height"

The daemon may still be starting up. Wait 30–60 seconds and try the status command again.
If it persists, check the logs:

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh log'
```

Look for error messages near the bottom.

---

### "My node is stuck and won't sync past a certain block"

Run the doctor:

```bash
bash doctor.sh
```

If it reports CORRUPT/STUCK, choose the bootstrap option to download a fresh blockchain.

---

### "I get 'Permission denied' when running commands"

Make sure you are logged in as the same user who downloaded the scripts
(not as a node user like snode1). Run commands from your main user account.

---

### "I forgot which username my node runs under"

```bash
bash transfer.sh --list
```

This shows all active node usernames and their keys.

Alternatively:

```bash
sudo ps aux | grep daemon
```

The first column shows the username for each running node.

---

### "The node service won't start"

Check if the service exists:

```bash
sudo systemctl status xeqmnode_snode1.service
```

If it says "not found", re-run the service setup:

```bash
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh setup_service'
sudo -H -u snode1 bash -c 'cd ~/xeqm-installer/ && bash xeqm-node.sh start'
```

---

### "I'm running out of disk space"

Check disk usage:

```bash
df -h /home
```

Check how much space the blockchain is using:

```bash
sudo du -sh /home/snode1/.equilibria
```

If multiple nodes share the same server, each has its own copy of the blockchain.
The doctor will warn you when free space drops below 20 GB.

---

### "My server's clock is wrong and I'm seeing NTP warnings"

```bash
sudo timedatectl set-ntp true
sudo systemctl restart systemd-timesyncd
sudo timedatectl
```

The output should show `NTP synchronized: yes`.

---

### "I need help"

If you're stuck, please reach out in the XEQM Labs community channels.
When asking for help, run the doctor and share the output — it gives helpers
the information they need quickly:

```bash
bash doctor.sh 2>&1 | tee doctor-output.txt
cat doctor-output.txt
```

---

*XEQM Labs Service Node Installer — v6.2*
