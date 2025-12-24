#!/bin/bash
#
# Setup prerequisites for SNO multi-region deployment
# Creates dummy dnsmasq services needed by the SNO deployment script
#

set -e

SNO_REGION1_NETWORK=${SNO_REGION1_NETWORK:-"sno-region1-net"}
SNO_REGION2_NETWORK=${SNO_REGION2_NETWORK:-"sno-region2-net"}

echo "=== Setting up SNO prerequisites ==="

# Create dummy dnsmasq service for Region 1
echo "Creating dummy dnsmasq service for Region 1..."
sudo tee /etc/systemd/system/${SNO_REGION1_NETWORK}-v6-dnsmasq.service > /dev/null << EOF
[Unit]
Description=Dummy dnsmasq service for SNO Region 1
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Create dummy dnsmasq service for Region 2
echo "Creating dummy dnsmasq service for Region 2..."
sudo tee /etc/systemd/system/${SNO_REGION2_NETWORK}-v6-dnsmasq.service > /dev/null << EOF
[Unit]
Description=Dummy dnsmasq service for SNO Region 2
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
echo "Reloading systemd..."
sudo systemctl daemon-reload

# Enable and start services
echo "Enabling and starting services..."
sudo systemctl enable ${SNO_REGION1_NETWORK}-v6-dnsmasq.service
sudo systemctl enable ${SNO_REGION2_NETWORK}-v6-dnsmasq.service
sudo systemctl start ${SNO_REGION1_NETWORK}-v6-dnsmasq.service
sudo systemctl start ${SNO_REGION2_NETWORK}-v6-dnsmasq.service

echo "=== SNO prerequisites setup complete ==="
