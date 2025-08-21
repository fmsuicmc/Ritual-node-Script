#!/usr/bin/env bash
set -euo pipefail

### ====== Editable defaults ======
PROJECT_NAME="hello-world"
REPO_URL="https://github.com/ritual-net/infernet-container-starter"
REPO_DIR="${HOME}/infernet-container-starter"
COORDINATOR_ADDR_DEFAULT="0x8D871Ef2826ac9001fB2e33fDD6379b6aaBF449c"
RPC_URL_DEFAULT="https://base-rpc.publicnode.com"
DOCKER_COMPOSE_VERSION_SET="1.0.0"   # docker-compose.yaml in deploy folder
### =================================

log() { echo -e "\n\033[1;36m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err() { echo -e "\033[1;31m[x] $*\033[0m"; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

require_root_tools() {
  log "Updating system and installing prerequisites..."
  sudo apt-get update -y
  sudo apt-get upgrade -y
  sudo apt-get install -y curl git jq lz4 build-essential screen ca-certificates gnupg lsb-release
}

install_docker() {
  if need_cmd docker && docker --help >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker (with compose) already installed."
    return
  fi

  log "Removing old Docker installations (if any)..."
  sudo apt-get remove -y docker docker-engine docker.io containerd runc || true

  log "Adding official Docker repository and installing..."
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  log "Adding current user to docker group (you may need to logout/login to take effect)."
  sudo usermod -aG docker "$USER" || true

  log "Testing Docker with hello-world..."
  docker run --rm hello-world || sudo docker run --rm hello-world || true
}

clone_repo() {
  if [ -d "$REPO_DIR/.git" ]; then
    log "Repository already present; pulling latest changes..."
    git -C "$REPO_DIR" pull --rebase --autostash || true
  else
    log "Cloning repository: $REPO_URL"
    git clone "$REPO_URL" "$REPO_DIR"
  fi
}

get_wallet_privkey() {
  if [ -n "${WALLET_PRIVATE_KEY:-}" ]; then
    PRIVKEY="$WALLET_PRIVATE_KEY"
  else
    read -r -p "Enter your wallet PRIVATE KEY (0x + 64 hex chars): " PRIVKEY
  fi
  if [[ ! "$PRIVKEY" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    warn "The private key format doesn't look like 0x + 64 hex chars. Proceeding anyway; make sure it's correct."
  fi
}

configure_files() {
  local coord="${1:-$COORDINATOR_ADDR_DEFAULT}"
  local rpc="${2:-$RPC_URL_DEFAULT}"
  local pk="$3"

  log "Updating deploy/config.json"
  local cfg="${REPO_DIR}/deploy/config.json"
  if [ -f "$cfg" ]; then
    tmp=$(mktemp)
    jq --arg c "$coord" --arg r "$rpc" --arg p "$pk" '
      if has("coordinator_address") then .coordinator_address=$c else . end
      | if has("rpc_url") then .rpc_url=$r else . end
      | if has("private_key") then .private_key=$p else . end
    ' "$cfg" > "$tmp" && mv "$tmp" "$cfg"
  else
    warn "deploy/config.json not found; skipping."
  fi

  log "Setting docker-compose.yaml version to ${DOCKER_COMPOSE_VERSION_SET}"
  local dcomp="${REPO_DIR}/deploy/docker-compose.yaml"
  if [ -f "$dcomp" ]; then
    sed -i -E "s/^(version:).*/\1 \"${DOCKER_COMPOSE_VERSION_SET}\"/I" "$dcomp" || true
  else
    warn "deploy/docker-compose.yaml not found; skipping."
  fi

  log "Adjusting project Makefile for RPC/keys (best-effort)"
  local mk="${REPO_DIR}/projects/${PROJECT_NAME}/contracts/Makefile"
  if [ -f "$mk" ]; then
    sed -i -E "s|^(RPC_URL[[:space:]]*:?=).*|\1 ${rpc}|I" "$mk" || true
    sed -i -E "s|^(PRIVATE_KEY[[:space:]]*:?=).*|\1 ${pk}|I" "$mk" || true
    sed -i -E "s|^(SENDER[[:space:]]*:?=).*|\1 ${pk}|I" "$mk" || true
  else
    warn "Project Makefile not found; skipping."
  fi

  log "Updating coordinator address inside Deploy.s.sol (best-effort)"
  local deploy_sol="${REPO_DIR}/projects/${PROJECT_NAME}/contracts/script/Deploy.s.sol"
  if [ -f "$deploy_sol" ]; then
    sed -i -E "s/(coordinator[_ ]?address[^=]*=[^0x]*)(0x[0-9a-fA-F]{40})/\1${coord}/g" "$deploy_sol" || true
    sed -i -E "s/(coordinator[^0-9A-Za-z]?)[^0x]*(0x[0-9a-fA-F]{40})/\1 ${coord}/g" "$deploy_sol" || true
  else
    warn "Deploy.s.sol not found; skipping."
  fi
}

deploy_containers() {
  log "Deploying containers via screen session (detached)..."
  pushd "$REPO_DIR" >/dev/null
  screen -S ritual -dm bash -lc "project=${PROJECT_NAME} make deploy-container || exit 0"
  popd >/dev/null

  log "docker compose down && up -d in deploy/"
  pushd "${REPO_DIR}/deploy" >/dev/null
  docker compose down || true
  docker compose up -d
  for svc in anvil-node hello-world deploy-node-1 deploy-fluentbit-1 deploy-redis-1; do
    docker restart "$svc" 2>/dev/null || true
  done
  popd >/dev/null
}

install_foundry() {
  if need_cmd forge; then
    log "Foundry already installed."
    return
  fi
  log "Installing Foundry..."
  mkdir -p "${HOME}/foundry"
  pushd "${HOME}/foundry" >/dev/null
  curl -L https://foundry.paradigm.xyz | bash
  if [ -f "${HOME}/.bashrc" ]; then source "${HOME}/.bashrc"; fi
  if [ -f "${HOME}/.zshrc" ]; then source "${HOME}/.zshrc"; fi
  foundryup
  popd >/dev/null
}

foundry_deps_and_deploy_contracts() {
  log "Installing forge dependencies for the project..."
  pushd "${REPO_DIR}/projects/${PROJECT_NAME}/contracts" >/dev/null
  forge install --no-commit foundry-rs/forge-std || true
  forge install --no-commit ritual-net/infernet-sdk || true
  popd >/dev/null

  log "Deploying contracts via make..."
  pushd "${REPO_DIR}" >/dev/null
  project="${PROJECT_NAME}" make deploy-contracts
  popd >/dev/null
}

set_call_contract_and_call() {
  local script_path="${REPO_DIR}/projects/${PROJECT_NAME}/contracts/script/CallContract.s.sol"
  if [ ! -f "$script_path" ]; then
    warn "CallContract.s.sol not found; skipping call-contract step."
    return
  fi

  echo
  read -r -p "Enter the deployed SaysHello/SaysGM contract ADDRESS (0x...): " SAYS_ADDR
  if [[ ! "$SAYS_ADDR" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    warn "The address format doesn't look valid; will attempt to replace anyway."
  fi

  log "Updating the address inside CallContract.s.sol (best-effort)"
  sed -i -E "s/(Says(GM|Hello)[^;=]*= *address\()0x[0-9a-fA-F]{40}(\))/\1${SAYS_ADDR}\3/g" "$script_path" || true
  sed -i -E "s/(SAYS_(GM|HELLO)[^=]*= *address\()0x[0-9a-fA-F]{40}(\))/\1${SAYS_ADDR}\3/g" "$script_path" || true
  sed -i -E "s/0x[0-9a-fA-F]{40}/${SAYS_ADDR}/g" "$script_path" || true

  log "Running: make call-contract"
  pushd "${REPO_DIR}" >/dev/null
  make call-contract project="${PROJECT_NAME}"
  popd >/dev/null
}

post_notes() {
  cat <<'MSG'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTES:
- After the initial run, open this page:
  https://basescan.org/address/0x8d871ef2826ac9001fb2e33fdd6379b6aabf449c#writeContract
  Wait about an hour, then use the `activateNode` function and make sure the tx succeeds.
- To follow logs:
  cd ~/infernet-container-starter/deploy
  docker compose logs -f
- Screen session:
  screen -ls            # list sessions
  screen -r ritual      # reattach
  Ctrl+A then D         # detach
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MSG
}

main() {
  require_root_tools
  install_docker
  clone_repo
  get_wallet_privkey
  configure_files "$COORDINATOR_ADDR_DEFAULT" "$RPC_URL_DEFAULT" "$PRIVKEY"
  deploy_containers
  install_foundry
  foundry_deps_and_deploy_contracts
  set_call_contract_and_call
  post_notes
  log "Done! Main steps completed."
}

main "$@"
