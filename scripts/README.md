# Hypertensor Node Setup Scripts

Quick setup scripts for running Hypertensor subnet nodes on VPS.

## Prerequisites

1. Python virtual environment with subnet package installed:
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -e .
   ```

2. Ensure port 31330 (TCP & UDP) is open:
   ```bash
   sudo ufw allow 31330/tcp
   sudo ufw allow 31330/udp
   ```

3. Sufficient funds in your coldkey for staking (100+ tokens by default)

## Quick Start

### 1. Full Setup (New Node)

```bash
# Generate all keys and register
./scripts/setup-node.sh setup
./scripts/setup-node.sh register

# Note the subnet_node_id from registration output, then:
SUBNET_NODE_ID=<your_id> ./scripts/setup-node.sh start
```

### 2. Step-by-Step

#### Generate Keys
```bash
./scripts/setup-node.sh setup
```
This creates:
- Coldkey (controls funds, staking)
- Hotkey (for node operations)
- Peer keys (main, bootnode, client)

All secrets are saved to `secrets.txt` - **back this up securely!**

#### Register Node
```bash
./scripts/setup-node.sh register
```
Note the `subnet_node_id` from the output (e.g., `'subnet_node_id': 4`).

#### Start Node
```bash
SUBNET_NODE_ID=4 ./scripts/setup-node.sh start
```

### 3. PM2 Setup (Recommended for VPS)

```bash
# Generate PM2 config
SUBNET_NODE_ID=4 ./scripts/setup-node.sh pm2

# Start with PM2
pm2 start ecosystem.config.js
pm2 save
pm2 startup  # Enable auto-start on boot
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SUBNET_ID` | 2 | Target subnet ID |
| `NODE_NAME` | node01 | Node name prefix for key files |
| `PORT` | 31330 | P2P port (TCP & UDP) |
| `DELEGATE_REWARD_RATE` | 0.125 | 12.5% delegate rewards |
| `STAKE_TO_BE_ADDED` | 100.00 | Initial stake amount |
| `MAX_BURN_AMOUNT` | 100.00 | Maximum burn for registration |
| `SUBNET_NODE_ID` | - | Required for start/pm2 commands |

## Multiple Nodes

To run multiple nodes, use different `NODE_NAME` and `PORT` values:

```bash
# Node 1
NODE_NAME=node01 PORT=31330 ./scripts/setup-node.sh setup
NODE_NAME=node01 PORT=31330 ./scripts/setup-node.sh register

# Node 2
NODE_NAME=node02 PORT=31331 ./scripts/setup-node.sh setup
NODE_NAME=node02 PORT=31331 ./scripts/setup-node.sh register
```

## File Structure

After setup:
```
.
├── keys/
│   ├── main-node01.key        # Main peer identity
│   ├── bootnode-node01.key    # Bootnode peer identity
│   └── client-node01.key      # Client peer identity
├── logs/
│   ├── node-out.log           # PM2 stdout logs
│   └── node-error.log         # PM2 stderr logs
├── secrets.txt                 # All keys and mnemonics (SECURE!)
├── ecosystem.config.js         # PM2 configuration
└── .env                        # Environment configuration
```

## Commands Reference

| Command | Description |
|---------|-------------|
| `./scripts/setup-node.sh setup` | Generate all keys |
| `./scripts/setup-node.sh register` | Register node on blockchain |
| `./scripts/setup-node.sh start` | Start subnet server |
| `./scripts/setup-node.sh pm2` | Generate PM2 config |
| `./scripts/setup-node.sh status` | Show node status |
| `./scripts/setup-node.sh all` | Setup + register + start |

## Troubleshooting

### Port not reachable
```bash
# Check if port is listening
ss -tlnp | grep 31330

# Check firewall
sudo ufw status
sudo iptables -L INPUT -n | grep 31330

# Test from external
nc -zv <your_public_ip> 31330
```

### Node not becoming active
- New nodes need to wait a few epochs after registration
- Ensure you have sufficient stake
- Check logs for validation errors

### PM2 issues
```bash
pm2 logs subnet-node-node01  # View logs
pm2 restart subnet-node-node01  # Restart
pm2 delete subnet-node-node01  # Remove
```
