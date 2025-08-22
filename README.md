# Infernet Base Node – One-Shot Setup

This repository contains a **single Bash script** that automates installing Docker, cloning Ritual's `infernet-container-starter`, configuring files, deploying containers, installing Foundry, deploying contracts, and running the sample call.

> **Script file:** `setup_infernet_base.sh`  
> Download: Use the link provided in chat next to this README.

---

## Prerequisites
- Ubuntu 20.04+
- A wallet on **Base** with ~\$10 ETH for gas.
- The wallet **private key** (keep it safe!).
- `sudo` access.

---

## Quick Start

Download and run the script directly from your GitHub repository:

```bash
# Download the script from GitHub (raw file)
wget https://raw.githubusercontent.com/fmsuicmc/Ritual-node-Script/main/setup_infernet_base.sh -O setup_infernet_base.sh

# Make it executable
chmod +x setup_infernet_base.sh

# Run the script
./setup_infernet_base.sh
```

The script will ask you for:
1. **Wallet Private Key** – `0x` + 64 hex chars.  
2. **Deployed SaysHello/SaysGM Contract Address** – after contracts are deployed.

You may skip prompts by pre-setting env vars (see **Non-Interactive Usage**).

---

## What the Script Does (Step-by-Step)
1. **System Prep**  
   - `apt-get update/upgrade`  
   - Installs: `curl`, `git`, `jq`, `lz4`, `build-essential`, `screen`, `ca-certificates`, `gnupg`, `lsb-release`

2. **Docker Installation** (if missing)  
   - Removes old Docker packages (best-effort)  
   - Adds official Docker repo, installs `docker-ce`, `docker-compose-plugin`  
   - Adds current user to `docker` group  
   - Runs `hello-world` test (best-effort)

3. **Clone / Update Repo**  
   - Clones `https://github.com/ritual-net/infernet-container-starter` into `~/infernet-container-starter` (or pulls latest if present).

4. **Config Files**  
   - Updates `deploy/config.json` fields (if present):  
     - `coordinator_address` → `0x8D871Ef2826ac9001fB2e33fDD6379b6aaBF449c`  
     - `rpc_url` → `https://base-rpc.publicnode.com`  
     - `private_key` → **your private key**
   - Sets `version: "1.0.0"` inside `deploy/docker-compose.yaml` (best-effort).
   - Updates project `Makefile` (best-effort): `RPC_URL`, `PRIVATE_KEY`, `SENDER`.
   - Updates `Deploy.s.sol` coordinator address (best-effort).

5. **Deploy Containers**  
   - Starts a detached `screen` session `ritual` to run `project=hello-world make deploy-container`  
   - Runs `docker compose down && docker compose up -d` in `deploy/`  
   - Restarts services if they exist: `anvil-node`, `hello-world`, `deploy-node-1`, `deploy-fluentbit-1`, `deploy-redis-1`.

6. **Install Foundry** (if missing)  
   - `curl -L https://foundry.paradigm.xyz | bash` then `foundryup`

7. **Contracts**  
   - `forge install` deps: `foundry-rs/forge-std`, `ritual-net/infernet-sdk`  
   - `make deploy-contracts`

8. **Call Script**  
   - Prompts for the **deployed SaysHello/SaysGM address**, updates `CallContract.s.sol` (best-effort)  
   - Runs `make call-contract project=hello-world`

9. **Post Notes**  
   - Prints reminders and useful commands (logs, screen, activation).

---

## Post-Deploy: Activate Node (Manual On-Chain Step)
Open (BaseScan – WriteContract tab):  
`https://basescan.org/address/0x8d871ef2826ac9001fb2e33fdd6379b6aabf449c#writeContract`

After ~1 hour, call **`activateNode`** and ensure the transaction succeeds.

---

## Logs & Screen
```bash
# Logs
cd ~/infernet-container-starter/deploy
docker compose logs -f

# Screen session
screen -ls         # list sessions
screen -r ritual   # reattach
# detach: Ctrl+A then D
```

---

## Configuration & Defaults
- **Project:** `hello-world`
- **Coordinator:** `0x8D871Ef2826ac9001fB2e33fDD6379b6aaBF449c`
- **RPC URL:** `https://base-rpc.publicnode.com`
- **Repo Directory:** `~/infernet-container-starter`
- **Compose Version (deploy/docker-compose.yaml):** `1.0.0`

You can change defaults at the top of the script.

---

## Non-Interactive Usage (Environment Variables)
To avoid prompts:
```bash
export WALLET_PRIVATE_KEY=0xYOURPRIVATEKEY...   # 64 hex chars
# (the SaysHello/SaysGM address is still requested later, after deployment)
./setup_infernet_base.sh
```

---

## Security Notes
- Your private key is only written **locally** to repo config files.  
- Do **NOT** share your private key. Consider using an **ephemeral** or **dedicated** key for experimentation.  
- Review the script before running if you have any concerns.

---

## Troubleshooting
- **Docker group not active:** Logout/login or run `newgrp docker`.  
- **Docker hello-world fails:** Try `sudo docker run --rm hello-world`.  
- **Foundry commands not found:** Open a new shell or `source ~/.bashrc` / `source ~/.zshrc`, then `foundryup`.  
- **RPC issues / gas errors:** Ensure wallet funded with Base ETH and RPC is reachable.  
- **Regex updates (best-effort) didn’t change files:** Manually edit:  
  - `deploy/config.json`  
  - `projects/hello-world/contracts/Makefile`  
  - `projects/hello-world/contracts/script/Deploy.s.sol`  
  - `projects/hello-world/contracts/script/CallContract.s.sol`

---

## Uninstall / Cleanup
```bash
# Stop containers
cd ~/infernet-container-starter/deploy
docker compose down

# Remove repo (careful)
rm -rf ~/infernet-container-starter
```

---

## Disclaimer
This script is provided as-is, best-effort. Always double-check the addresses and values you write on-chain.

by fmusicmc https://x.com/mr_satoshiii
