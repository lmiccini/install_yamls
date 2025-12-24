#!/bin/bash
#
# Setup prerequisites for SNO multi-region deployment
# Creates libvirt networks and dummy dnsmasq services needed by the SNO deployment script
#

set -e

SNO_REGION1_NETWORK=${SNO_REGION1_NETWORK:-"sno-region1-net"}
SNO_REGION2_NETWORK=${SNO_REGION2_NETWORK:-"sno-region2-net"}
SNO_REGION1_NETWORK_CIDR=${SNO_REGION1_NETWORK_CIDR:-"192.168.130.0/24"}
SNO_REGION2_NETWORK_CIDR=${SNO_REGION2_NETWORK_CIDR:-"192.168.131.0/24"}

echo "=== Setting up SNO prerequisites ==="

# Create libvirt network for Region 1
echo "Creating libvirt network for Region 1..."
if ! sudo virsh net-info ${SNO_REGION1_NETWORK} &>/dev/null; then
    cat > /tmp/sno-region1-net.xml << EOF
<network>
  <name>${SNO_REGION1_NETWORK}</name>
  <forward mode='nat'/>
  <bridge name='virbr-r1' stp='on' delay='0'/>
  <ip address='192.168.130.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.130.2' end='192.168.130.254'/>
    </dhcp>
  </ip>
</network>
EOF
    sudo virsh net-define /tmp/sno-region1-net.xml
    sudo virsh net-start ${SNO_REGION1_NETWORK}
    sudo virsh net-autostart ${SNO_REGION1_NETWORK}
    rm -f /tmp/sno-region1-net.xml
    echo "Network ${SNO_REGION1_NETWORK} created"
else
    echo "Network ${SNO_REGION1_NETWORK} already exists"
fi

# Ensure network is active
if ! sudo virsh net-info ${SNO_REGION1_NETWORK} | grep -q "Active:.*yes"; then
    echo "Network ${SNO_REGION1_NETWORK} is not active, starting it..."
    sudo virsh net-start ${SNO_REGION1_NETWORK} || {
        echo "ERROR: Failed to start network ${SNO_REGION1_NETWORK}"
        echo "This might be due to a conflicting network or bridge."
        echo "Check with: sudo virsh net-list --all"
        exit 1
    }
fi

# Create libvirt network for Region 2
echo "Creating libvirt network for Region 2..."
if ! sudo virsh net-info ${SNO_REGION2_NETWORK} &>/dev/null; then
    cat > /tmp/sno-region2-net.xml << EOF
<network>
  <name>${SNO_REGION2_NETWORK}</name>
  <forward mode='nat'/>
  <bridge name='virbr-r2' stp='on' delay='0'/>
  <ip address='192.168.131.1' netmask='255.255.255.0'>
    <dhcp>
      <range start='192.168.131.2' end='192.168.131.254'/>
    </dhcp>
  </ip>
</network>
EOF
    sudo virsh net-define /tmp/sno-region2-net.xml
    sudo virsh net-start ${SNO_REGION2_NETWORK}
    sudo virsh net-autostart ${SNO_REGION2_NETWORK}
    rm -f /tmp/sno-region2-net.xml
    echo "Network ${SNO_REGION2_NETWORK} created"
else
    echo "Network ${SNO_REGION2_NETWORK} already exists"
fi

# Ensure network is active
if ! sudo virsh net-info ${SNO_REGION2_NETWORK} | grep -q "Active:.*yes"; then
    echo "Network ${SNO_REGION2_NETWORK} is not active, starting it..."
    sudo virsh net-start ${SNO_REGION2_NETWORK} || {
        echo "ERROR: Failed to start network ${SNO_REGION2_NETWORK}"
        echo "This might be due to a conflicting network or bridge."
        echo "Check with: sudo virsh net-list --all"
        exit 1
    }
fi

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
