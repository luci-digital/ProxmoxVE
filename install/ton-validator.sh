#!/usr/bin/env bash

# TON Validator Node Installation Script for Proxmox VE
# Author: Luci Digital
# License: CC0-1.0 | https://github.com/luci-digital/ProxmoxVE/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os


msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
$STD apt-get install -y curl 
sudo mc git jq build-essential
msg_ok "Installed Dependencies"

motd_ssh
customize

# Prompt for TON Validator Account Variables
msg_info "TON Validator Account Setup"
read -r -p "Enter Validator Address [default: empty]: " VALIDATOR_ADDRESS
VALIDATOR_ADDRESS=${VALIDATOR_ADDRESS:-"YOUR_VALIDATOR_ADDRESS"}

# Auto-detect Public IP
PUBLIC_IP=$(curl -s ifconfig.me)
read -r -p "Enter Public IP [detected: $PUBLIC_IP]: " CUSTOM_PUBLIC_IP
PUBLIC_IP=${CUSTOM_PUBLIC_IP:-$PUBLIC_IP}

read -r -p "Enter TON Wallet Address [default: empty]: " WALLET_ADDRESS
WALLET_ADDRESS=${WALLET_ADDRESS:-"YOUR_TON_WALLET_ADDRESS"}

read -r -p "Enter Validator Port [default: 5333]: " VALIDATOR_PORT
VALIDATOR_PORT=${VALIDATOR_PORT:-5333}

# Store account variables
CONFIG_FILE="/opt/tonvalidator/config.json"
mkdir -p /opt/tonvalidator
cat <<EOF > "$CONFIG_FILE"
{
  "validator_address": "${VALIDATOR_ADDRESS}",
  "public_ip": "${PUBLIC_IP}",
  "port": ${VALIDATOR_PORT},
  "wallet_address": "${WALLET_ADDRESS}"
}
EOF
msg_ok "Stored Validator Configuration"

# Create LXC or VM
read -r -p "Do you want to create a (1) VM or (2) LXC container? [1/2]: " CHOICE
if [[ "$CHOICE" == "1" ]]; then
  VM_ID=100
  STORAGE_POOL="local-lvm"
  RAM=4096
  CORES=2
  DISK_SIZE=30G
  NET_BRIDGE="vmbr0"
  ISO_IMAGE="debian-12.iso"

  msg_info "Creating VM with ID $VM_ID"
  qm create $VM_ID --name ton-validator --memory $RAM --cores $CORES --net0 virtio,bridge=$NET_BRIDGE
  qm set $VM_ID --scsihw virtio-scsi-pci --scsi0 $STORAGE_POOL:$DISK_SIZE
  qm set $VM_ID --boot order=scsi0
  qm set $VM_ID --ide2 $STORAGE_POOL:iso/$ISO_IMAGE,media=cdrom
  qm start $VM_ID
  msg_ok "VM Created and Started"

  exit 0

elif [[ "$CHOICE" == "2" ]]; then
  CT_ID=200
  STORAGE_POOL="local-lvm"
  LXC_TEMPLATE="local:vztmpl/debian-12-standard_12.0-1_amd64.tar.zst"
  RAM=4096
  CORES=2
  DISK_SIZE=30G
  NET_BRIDGE="vmbr0"

  msg_info "Creating LXC container with ID $CT_ID"
  pct create $CT_ID $LXC_TEMPLATE --memory $RAM --cores $CORES --rootfs $STORAGE_POOL:$DISK_SIZE --net0 name=eth0,bridge=$NET_BRIDGE,ip=dhcp
  pct set $CT_ID --unprivileged 1 --features nesting=1
  pct push $CT_ID "$CONFIG_FILE" /root/config.json
  pct start $CT_ID
  msg_ok "LXC Container Created and Started"

  exit 0

else
  msg_error "Invalid selection. Please choose 1 for VM or 2 for LXC."
  exit 1
fi

# Inside VM or LXC, install validator
msg_info "Installing TON Validator Node"
if [ -f "/root/config.json" ]; then
  source /root/config.json
fi

msg_info "Cloning TON Blockchain Repository"
git clone https://github.com/ton-blockchain/ton.git /opt/tonvalidator/ton
cd /opt/tonvalidator/ton
git pull
msg_ok "Cloned and Updated Repository"

msg_info "Building TON Validator Node"
make
msg_ok "Built TON Validator Node"

msg_info "Moving Binaries"
cp bin/* /usr/local/bin/
msg_ok "Moved Binaries"

msg_info "Creating TON Validator Service"
cat <<EOF > /etc/systemd/system/ton-validator.service
[Unit]
Description=TON Validator Node
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/ton-validator --config /opt/tonvalidator/config.json
Restart=always
LimitNOFILE=1024000

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now ton-validator
msg_ok "TON Validator Service Started"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

msg_info "Installation Completed"
echo -e "
╔════════════════════════════════════════════════════════════════╗
║                 TON VALIDATOR INSTALLATION COMPLETE            ║
╚════════════════════════════════════════════════════════════════╝

→ Status: $(systemctl is-active ton-validator)
→ Login: ssh root@${PUBLIC_IP}
→ Check service: systemctl status ton-validator
→ View logs: journalctl -u ton-validator -f
→ Config file: /opt/tonvalidator/config.json

Don't forget to:
1. Secure your validator key and wallet address.
2. Ensure port ${VALIDATOR_PORT} is open.
3. Monitor your validator node for uptime and performance.

🚀 Installation script from: https://github.com/luci-digital/ProxmoxVE
"
