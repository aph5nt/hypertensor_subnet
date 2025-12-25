#!/bin/bash

# Hypertensor Subnet Node Setup Script
# This script generates keys, registers a node, and starts it
# Usage: ./setup-node.sh [setup|register|start|all]

set -e

# File paths - determine project directory first
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VENV_DIR="${PROJECT_DIR}/.venv"

# Auto-activate virtual environment if it exists and we're not already in it
if [ -d "$VENV_DIR" ] && [ -z "$VIRTUAL_ENV" ]; then
    echo "[INFO] Activating Python virtual environment..."
    source "${VENV_DIR}/bin/activate"
elif [ -z "$VIRTUAL_ENV" ]; then
    echo "[ERROR] Virtual environment not found at ${VENV_DIR}"
    echo "[INFO] Create it with: python3 -m venv ${VENV_DIR} && source ${VENV_DIR}/bin/activate && pip install -e ."
    exit 1
fi

# Configuration - Edit these values before running
SUBNET_ID="${SUBNET_ID:-2}"
DELEGATE_REWARD_RATE="${DELEGATE_REWARD_RATE:-0.125}"
STAKE_TO_BE_ADDED="${STAKE_TO_BE_ADDED:-100.00}"
MAX_BURN_AMOUNT="${MAX_BURN_AMOUNT:-100.00}"
NODE_NAME="${NODE_NAME:-node01}"
PORT="${PORT:-31330}"
PUBLIC_IP="${PUBLIC_IP:-}"  # Set this to your VPS public IP to avoid auto-detection

# File paths (SCRIPT_DIR and PROJECT_DIR defined above)
KEYS_DIR="${PROJECT_DIR}/keys"
ENV_FILE="${PROJECT_DIR}/.env"
SECRETS_FILE="${PROJECT_DIR}/secrets.txt"
NODE_CONFIG_FILE="${PROJECT_DIR}/node-config.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

get_public_ip() {
    # Use PUBLIC_IP from environment/config if set, otherwise auto-detect
    if [ -n "$PUBLIC_IP" ]; then
        echo "$PUBLIC_IP"
    else
        curl -s --max-time 5 ifconfig.me || curl -s --max-time 5 icanhazip.com || curl -s --max-time 5 ipinfo.io/ip
    fi
}

generate_coldkey() {
    log_info "Generating coldkey (12 words)..."
    
    COLDKEY_OUTPUT=$(generate-key --words 12 2>&1)
    
    COLDKEY_PHRASE=$(echo "$COLDKEY_OUTPUT" | grep -A2 "mnemonic phrase" | tail -1 | xargs)
    COLDKEY_PRIVATE=$(echo "$COLDKEY_OUTPUT" | grep -A2 "Private key:" | tail -1 | xargs)
    COLDKEY_ADDRESS=$(echo "$COLDKEY_OUTPUT" | grep -A2 "account_id" | tail -1 | xargs)
    
    echo "COLDKEY_PHRASE=\"$COLDKEY_PHRASE\"" >> "$SECRETS_FILE"
    echo "COLDKEY_PRIVATE=\"$COLDKEY_PRIVATE\"" >> "$SECRETS_FILE"
    echo "COLDKEY_ADDRESS=\"$COLDKEY_ADDRESS\"" >> "$SECRETS_FILE"
    
    # Update .env with PHRASE
    if grep -q "^PHRASE=" "$ENV_FILE" 2>/dev/null; then
        sed -i "s|^PHRASE=.*|PHRASE=$COLDKEY_PHRASE|" "$ENV_FILE"
    else
        echo "PHRASE=$COLDKEY_PHRASE" >> "$ENV_FILE"
    fi
    
    log_success "Coldkey generated: $COLDKEY_ADDRESS"
}

generate_hotkey() {
    log_info "Generating hotkey (12 words)..."
    
    HOTKEY_OUTPUT=$(generate-key --words 12 2>&1)
    
    HOTKEY_PHRASE=$(echo "$HOTKEY_OUTPUT" | grep -A2 "mnemonic phrase" | tail -1 | xargs)
    HOTKEY_PRIVATE=$(echo "$HOTKEY_OUTPUT" | grep -A2 "Private key:" | tail -1 | xargs)
    HOTKEY_ADDRESS=$(echo "$HOTKEY_OUTPUT" | grep -A2 "account_id" | tail -1 | xargs)
    
    echo "" >> "$SECRETS_FILE"
    echo "HOTKEY_PHRASE=\"$HOTKEY_PHRASE\"" >> "$SECRETS_FILE"
    echo "HOTKEY_PRIVATE=\"$HOTKEY_PRIVATE\"" >> "$SECRETS_FILE"
    echo "HOTKEY_ADDRESS=\"$HOTKEY_ADDRESS\"" >> "$SECRETS_FILE"
    
    log_success "Hotkey generated: $HOTKEY_ADDRESS"
}

generate_peer_keys() {
    log_info "Generating peer keys for $NODE_NAME..."
    
    mkdir -p "$KEYS_DIR"
    
    KEYGEN_OUTPUT=$(keygen \
        --path "${KEYS_DIR}/main-${NODE_NAME}.key" \
        --bootstrap_path "${KEYS_DIR}/bootnode-${NODE_NAME}.key" \
        --client_path "${KEYS_DIR}/client-${NODE_NAME}.key" \
        --key_type ed25519 2>&1)
    
    MAIN_PEER_ID=$(echo "$KEYGEN_OUTPUT" | grep "^.*Peer ID:" | head -1 | awk '{print $NF}')
    BOOTNODE_PEER_ID=$(echo "$KEYGEN_OUTPUT" | grep "Bootstrap Peer ID:" | awk '{print $NF}')
    CLIENT_PEER_ID=$(echo "$KEYGEN_OUTPUT" | grep "Client Peer ID:" | awk '{print $NF}')
    
    echo "" >> "$SECRETS_FILE"
    echo "# Peer Keys for $NODE_NAME" >> "$SECRETS_FILE"
    echo "MAIN_PEER_ID=\"$MAIN_PEER_ID\"" >> "$SECRETS_FILE"
    echo "BOOTNODE_PEER_ID=\"$BOOTNODE_PEER_ID\"" >> "$SECRETS_FILE"
    echo "CLIENT_PEER_ID=\"$CLIENT_PEER_ID\"" >> "$SECRETS_FILE"
    
    log_success "Peer keys generated:"
    echo "  Main Peer ID: $MAIN_PEER_ID"
    echo "  Bootnode Peer ID: $BOOTNODE_PEER_ID"
    echo "  Client Peer ID: $CLIENT_PEER_ID"
}

setup_keys() {
    log_info "=== Key Generation Setup ==="
    
    # Backup existing secrets
    if [ -f "$SECRETS_FILE" ]; then
        cp "$SECRETS_FILE" "${SECRETS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log_warn "Existing secrets backed up"
    fi
    
    # Create new secrets file with header
    echo "# Hypertensor Node Secrets - Generated $(date)" > "$SECRETS_FILE"
    echo "# KEEP THIS FILE SECURE - DO NOT SHARE" >> "$SECRETS_FILE"
    echo "" >> "$SECRETS_FILE"
    
    generate_coldkey
    generate_hotkey
    generate_peer_keys
    
    chmod 600 "$SECRETS_FILE"
    chmod 600 "${KEYS_DIR}"/*.key 2>/dev/null || true
    
    log_success "All keys generated and saved to $SECRETS_FILE"
    log_warn "IMPORTANT: Back up $SECRETS_FILE and keys/ directory securely!"
}

load_secrets() {
    if [ ! -f "$SECRETS_FILE" ]; then
        log_error "Secrets file not found: $SECRETS_FILE"
        log_info "Run './setup-node.sh setup' first to generate keys"
        exit 1
    fi
    
    source "$SECRETS_FILE"
    
    # Also load node config if exists
    if [ -f "$NODE_CONFIG_FILE" ]; then
        source "$NODE_CONFIG_FILE"
    fi
}

save_node_config() {
    echo "# Node Configuration - Auto-generated" > "$NODE_CONFIG_FILE"
    echo "SUBNET_NODE_ID=\"$SUBNET_NODE_ID\"" >> "$NODE_CONFIG_FILE"
    echo "SUBNET_ID=\"$SUBNET_ID\"" >> "$NODE_CONFIG_FILE"
    echo "NODE_NAME=\"$NODE_NAME\"" >> "$NODE_CONFIG_FILE"
    echo "PORT=\"$PORT\"" >> "$NODE_CONFIG_FILE"
    if [ -n "$PUBLIC_IP" ]; then
        echo "PUBLIC_IP=\"$PUBLIC_IP\"" >> "$NODE_CONFIG_FILE"
    fi
    chmod 600 "$NODE_CONFIG_FILE"
}

extract_subnet_node_id() {
    # Extract subnet_node_id from registration output
    local output="$1"
    
    # Try to extract from 'subnet_node_id': X pattern
    SUBNET_NODE_ID=$(echo "$output" | grep -oP "'subnet_node_id':\s*\K\d+" | head -1)
    
    if [ -z "$SUBNET_NODE_ID" ]; then
        # Fallback: try SubnetNodeRegistered event format
        SUBNET_NODE_ID=$(echo "$output" | grep -oP "SubnetNodeRegistered.*'subnet_node_id':\s*\K\d+" | head -1)
    fi
    
    if [ -z "$SUBNET_NODE_ID" ]; then
        # Another fallback: id field in data
        SUBNET_NODE_ID=$(echo "$output" | grep -oP "'data':\s*\{'id':\s*\K\d+" | head -1)
    fi
}

register_node() {
    log_info "=== Node Registration ==="
    
    load_secrets
    
    if [ -z "$HOTKEY_ADDRESS" ] || [ -z "$COLDKEY_PRIVATE" ] || [ -z "$MAIN_PEER_ID" ]; then
        log_error "Missing required keys. Run './setup-node.sh setup' first"
        exit 1
    fi
    
    log_info "Registering node on subnet $SUBNET_ID..."
    log_info "Hotkey: $HOTKEY_ADDRESS"
    log_info "Coldkey: $COLDKEY_ADDRESS"
    log_info "Peer ID: $MAIN_PEER_ID"
    
    # Capture registration output
    REGISTER_OUTPUT=$(register-node \
        --subnet_id "$SUBNET_ID" \
        --hotkey "$HOTKEY_ADDRESS" \
        --peer_id "$MAIN_PEER_ID" \
        --bootnode_peer_id "$BOOTNODE_PEER_ID" \
        --client_peer_id "$CLIENT_PEER_ID" \
        --delegate_reward_rate "$DELEGATE_REWARD_RATE" \
        --stake_to_be_added "$STAKE_TO_BE_ADDED" \
        --max_burn_amount "$MAX_BURN_AMOUNT" \
        --private_key "$COLDKEY_PRIVATE" 2>&1) || true
    
    echo "$REGISTER_OUTPUT"
    
    # Extract subnet_node_id from output
    extract_subnet_node_id "$REGISTER_OUTPUT"
    
    if [ -n "$SUBNET_NODE_ID" ]; then
        log_success "Extracted Subnet Node ID: $SUBNET_NODE_ID"
        
        # Save to config file for future use
        save_node_config
        
        # Also append to secrets file
        echo "" >> "$SECRETS_FILE"
        echo "# Registration Info" >> "$SECRETS_FILE"
        echo "SUBNET_NODE_ID=\"$SUBNET_NODE_ID\"" >> "$SECRETS_FILE"
        
        log_success "Node registration complete! Subnet Node ID saved automatically."
    else
        log_warn "Could not auto-extract subnet_node_id from output."
        log_info "Please check the output above and manually set SUBNET_NODE_ID in node-config.env"
    fi
}

start_node() {
    log_info "=== Starting Node ==="
    
    load_secrets
    
    PUBLIC_IP=$(get_public_ip)
    log_info "Detected public IP: $PUBLIC_IP"
    
    if [ -z "$HOTKEY_PRIVATE" ] || [ -z "$MAIN_PEER_ID" ]; then
        log_error "Missing required keys. Run './setup-node.sh setup' first"
        exit 1
    fi
    
    if [ -z "$SUBNET_NODE_ID" ]; then
        log_error "SUBNET_NODE_ID not found. Run './setup-node.sh register' first"
        exit 1
    fi
    
    log_info "Starting subnet server..."
    log_info "Subnet ID: $SUBNET_ID"
    log_info "Subnet Node ID: $SUBNET_NODE_ID"
    log_info "Public IP: $PUBLIC_IP"
    log_info "Port: $PORT"
    
    subnet-server-mock \
        --host_maddrs /ip4/0.0.0.0/tcp/${PORT} /ip4/0.0.0.0/udp/${PORT}/quic-v1 \
        --announce_maddrs /ip4/${PUBLIC_IP}/tcp/${PORT} /ip4/${PUBLIC_IP}/udp/${PORT}/quic-v1 \
        --identity_path "${KEYS_DIR}/main-${NODE_NAME}.key" \
        --subnet_id "$SUBNET_ID" \
        --subnet_node_id "$SUBNET_NODE_ID" \
        --private_key "$HOTKEY_PRIVATE" \
        --initial_peers /ip4/18.188.231.198/tcp/31330/p2p/12D3KooWGv47krKG6j6MtGLdLYqJHratRJKx9xFTsDbzTTUPNgUB /ip4/18.188.231.198/udp/31330/quic-v1/p2p/12D3KooWGv47krKG6j6MtGLdLYqJHratRJKx9xFTsDbzTTUPNgUB
}

generate_pm2_config() {
    log_info "=== Generating PM2 Configuration ==="
    
    load_secrets
    
    PUBLIC_IP=$(get_public_ip)
    
    if [ -z "$SUBNET_NODE_ID" ]; then
        log_error "SUBNET_NODE_ID not found. Run './setup-node.sh register' first"
        exit 1
    fi
    
    mkdir -p "${PROJECT_DIR}/logs"
    
    cat > "${PROJECT_DIR}/ecosystem.config.js" << EOF
module.exports = {
  apps: [
    {
      name: 'subnet-node-${NODE_NAME}',
      script: 'subnet-server-mock',
      interpreter: 'none',
      args: [
        '--host_maddrs', '/ip4/0.0.0.0/tcp/${PORT}', '/ip4/0.0.0.0/udp/${PORT}/quic-v1',
        '--announce_maddrs', '/ip4/${PUBLIC_IP}/tcp/${PORT}', '/ip4/${PUBLIC_IP}/udp/${PORT}/quic-v1',
        '--identity_path', '${KEYS_DIR}/main-${NODE_NAME}.key',
        '--subnet_id', '${SUBNET_ID}',
        '--subnet_node_id', '${SUBNET_NODE_ID}',
        '--private_key', '${HOTKEY_PRIVATE}',
        '--initial_peers', '/ip4/18.188.231.198/tcp/31330/p2p/12D3KooWGv47krKG6j6MtGLdLYqJHratRJKx9xFTsDbzTTUPNgUB', '/ip4/18.188.231.198/udp/31330/quic-v1/p2p/12D3KooWGv47krKG6j6MtGLdLYqJHratRJKx9xFTsDbzTTUPNgUB'
      ],
      cwd: '${PROJECT_DIR}',
      env: {
        PATH: process.env.PATH
      },
      autorestart: true,
      max_restarts: 10,
      restart_delay: 5000,
      watch: false,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      error_file: '${PROJECT_DIR}/logs/node-error.log',
      out_file: '${PROJECT_DIR}/logs/node-out.log',
      merge_logs: true
    }
  ]
};
EOF

    log_success "PM2 config generated: ${PROJECT_DIR}/ecosystem.config.js"
    log_info "To start with PM2:"
    echo "  pm2 start ecosystem.config.js"
    echo "  pm2 save"
    echo "  pm2 startup  # to auto-start on boot"
}

show_status() {
    log_info "=== Node Status ==="
    
    if [ -f "$SECRETS_FILE" ]; then
        log_success "Secrets file exists"
        source "$SECRETS_FILE"
        echo "  Coldkey: ${COLDKEY_ADDRESS:-Not set}"
        echo "  Hotkey: ${HOTKEY_ADDRESS:-Not set}"
        echo "  Peer ID: ${MAIN_PEER_ID:-Not set}"
        echo "  Subnet Node ID: ${SUBNET_NODE_ID:-Not set}"
    else
        log_warn "No secrets file found"
    fi
    
    if [ -d "$KEYS_DIR" ]; then
        KEY_COUNT=$(ls -1 "${KEYS_DIR}"/*.key 2>/dev/null | wc -l)
        log_success "Keys directory exists with $KEY_COUNT key files"
    else
        log_warn "No keys directory found"
    fi
    
    # Check if node is running
    if pgrep -f "subnet-server-mock" > /dev/null; then
        log_success "Node is running"
    else
        log_warn "Node is not running"
    fi
    
    # Check port
    if ss -tlnp | grep -q ":${PORT}"; then
        log_success "Port $PORT is listening"
    else
        log_warn "Port $PORT is not listening"
    fi
}

run_all() {
    log_info "=== Full Node Setup (Automated) ==="
    
    # Step 1: Setup keys
    setup_keys
    echo ""
    
    # Step 2: Fund check warning
    log_warn "IMPORTANT: Before proceeding, ensure your coldkey has funds!"
    log_info "Coldkey address: $COLDKEY_ADDRESS"
    log_info "Required: At least ${STAKE_TO_BE_ADDED} tokens for staking"
    echo ""
    echo -n "Press Enter when your coldkey is funded (or Ctrl+C to cancel)..."
    read
    echo ""
    
    # Step 3: Register node
    register_node
    echo ""
    
    # Step 4: Generate PM2 config
    generate_pm2_config
    echo ""
    
    # Step 5: Start node
    log_info "Starting node..."
    start_node
}

deploy() {
    # Fully automated deploy - assumes keys exist and are funded
    log_info "=== Deploying Node ==="
    
    load_secrets
    
    if [ -z "$SUBNET_NODE_ID" ]; then
        log_error "SUBNET_NODE_ID not found. Run './setup-node.sh register' first or './setup-node.sh all' for full setup"
        exit 1
    fi
    
    # Generate PM2 config
    generate_pm2_config
    
    # Start with PM2
    log_info "Starting node with PM2..."
    pm2 start "${PROJECT_DIR}/ecosystem.config.js"
    pm2 save
    
    log_success "Node deployed and running!"
    echo ""
    echo "Useful PM2 commands:"
    echo "  pm2 logs subnet-node-${NODE_NAME}    # View logs"
    echo "  pm2 status                           # Check status"
    echo "  pm2 restart subnet-node-${NODE_NAME} # Restart"
    echo "  pm2 startup                          # Enable auto-start on boot"
}

show_help() {
    echo "Hypertensor Subnet Node Setup Script"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  setup     - Generate all keys (coldkey, hotkey, peer keys)"
    echo "  register  - Register node on the blockchain (auto-saves subnet_node_id)"
    echo "  start     - Start the subnet server"
    echo "  pm2       - Generate PM2 ecosystem config"
    echo "  deploy    - Generate PM2 config and start (requires prior registration)"
    echo "  status    - Show current node status"
    echo "  all       - Full automated setup: keys -> register -> pm2 -> start"
    echo ""
    echo "Typical Usage:"
    echo "  1. First time setup:  $0 all"
    echo "     (This does everything in one go, just fund your coldkey when prompted)"
    echo ""
    echo "  2. On new VPS with existing secrets.txt:"
    echo "     Copy secrets.txt and keys/ folder to VPS, then:"
    echo "     $0 deploy"
    echo ""
    echo "Environment Variables (optional overrides):"
    echo "  SUBNET_ID              - Subnet ID (default: 2)"
    echo "  NODE_NAME              - Node name prefix (default: node01)"
    echo "  PORT                   - Port number (default: 31330)"
    echo "  DELEGATE_REWARD_RATE   - Delegate reward rate (default: 0.125)"
    echo "  STAKE_TO_BE_ADDED      - Stake amount (default: 100.00)"
    echo "  MAX_BURN_AMOUNT        - Max burn amount (default: 100.00)"
    echo ""
}

# Main
case "${1:-help}" in
    setup)
        setup_keys
        ;;
    register)
        register_node
        ;;
    start)
        start_node
        ;;
    pm2)
        generate_pm2_config
        ;;
    deploy)
        deploy
        ;;
    status)
        show_status
        ;;
    all)
        run_all
        ;;
    *)
        show_help
        ;;
esac
