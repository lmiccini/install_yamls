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
SNO_REGION1_HOST_IP=${SNO_REGION1_HOST_IP:-"192.168.130.10"}
SNO_REGION1_HOST_MAC=${SNO_REGION1_HOST_MAC:-"52:54:00:aa:bb:01"}
SNO_REGION2_HOST_IP=${SNO_REGION2_HOST_IP:-"192.168.131.10"}
SNO_REGION2_HOST_MAC=${SNO_REGION2_HOST_MAC:-"52:54:00:aa:bb:02"}

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
      <range start='192.168.130.100' end='192.168.130.254'/>
      <host mac='${SNO_REGION1_HOST_MAC}' ip='${SNO_REGION1_HOST_IP}'/>
    </dhcp>
  </ip>
</network>
EOF
    sudo virsh net-define /tmp/sno-region1-net.xml
    sudo virsh net-start ${SNO_REGION1_NETWORK}
    sudo virsh net-autostart ${SNO_REGION1_NETWORK}
    rm -f /tmp/sno-region1-net.xml
    echo "Network ${SNO_REGION1_NETWORK} created with static DHCP for ${SNO_REGION1_HOST_MAC} -> ${SNO_REGION1_HOST_IP}"
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
      <range start='192.168.131.100' end='192.168.131.254'/>
      <host mac='${SNO_REGION2_HOST_MAC}' ip='${SNO_REGION2_HOST_IP}'/>
    </dhcp>
  </ip>
</network>
EOF
    sudo virsh net-define /tmp/sno-region2-net.xml
    sudo virsh net-start ${SNO_REGION2_NETWORK}
    sudo virsh net-autostart ${SNO_REGION2_NETWORK}
    rm -f /tmp/sno-region2-net.xml
    echo "Network ${SNO_REGION2_NETWORK} created with static DHCP for ${SNO_REGION2_HOST_MAC} -> ${SNO_REGION2_HOST_IP}"
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

# Install dnsmasq if not present
if ! command -v dnsmasq &> /dev/null; then
    echo "Installing dnsmasq..."
    sudo dnf install -y dnsmasq
fi

# Create dnsmasq configuration for SNO wildcard DNS
echo "Configuring dnsmasq for SNO wildcard DNS..."
sudo mkdir -p /etc/dnsmasq.d

sudo tee /etc/dnsmasq.d/sno-multiregion.conf > /dev/null << EOF
# Listen on localhost only for SNO DNS
listen-address=127.0.0.1
bind-interfaces

# Don't read /etc/hosts for these domains
no-hosts

# Wildcard DNS for Region 1
address=/apps.sno-region1.example.com/192.168.130.10
address=/sno-region1.example.com/192.168.130.10

# Wildcard DNS for Region 2
address=/apps.sno-region2.example.com/192.168.131.10
address=/sno-region2.example.com/192.168.131.10

# Specific host records for APIs
host-record=api.sno-region1.example.com,192.168.130.10
host-record=api-int.sno-region1.example.com,192.168.130.10
host-record=api.sno-region2.example.com,192.168.131.10
host-record=api-int.sno-region2.example.com,192.168.131.10
EOF

# Enable and start dnsmasq
echo "Starting dnsmasq..."
sudo systemctl enable dnsmasq
sudo systemctl restart dnsmasq

# Configure NetworkManager to use local dnsmasq for SNO domains
if systemctl is-active NetworkManager &>/dev/null; then
    echo "Configuring NetworkManager to use dnsmasq for SNO domains..."
    sudo tee /etc/NetworkManager/dnsmasq.d/sno-domains.conf > /dev/null << EOF
# Forward SNO domain queries to local dnsmasq
server=/sno-region1.example.com/127.0.0.1
server=/sno-region2.example.com/127.0.0.1
EOF
    sudo systemctl reload NetworkManager
fi

# Create dummy systemd services (for compatibility with SNO script)
sudo tee /etc/systemd/system/${SNO_REGION1_NETWORK}-v6-dnsmasq.service > /dev/null << EOF
[Unit]
Description=Dummy placeholder for SNO Region 1 (real DNS in dnsmasq)
After=dnsmasq.service

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo tee /etc/systemd/system/${SNO_REGION2_NETWORK}-v6-dnsmasq.service > /dev/null << EOF
[Unit]
Description=Dummy placeholder for SNO Region 2 (real DNS in dnsmasq)
After=dnsmasq.service

[Service]
Type=oneshot
ExecStart=/bin/true
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable ${SNO_REGION1_NETWORK}-v6-dnsmasq.service
sudo systemctl enable ${SNO_REGION2_NETWORK}-v6-dnsmasq.service
sudo systemctl start ${SNO_REGION1_NETWORK}-v6-dnsmasq.service
sudo systemctl start ${SNO_REGION2_NETWORK}-v6-dnsmasq.service

# Add DNS entries to /etc/hosts for SNO clusters
echo "Adding DNS entries to /etc/hosts..."

# Region 1 entries
if ! grep -q "api.sno-region1.example.com" /etc/hosts 2>/dev/null; then
    echo "192.168.130.10 api.sno-region1.example.com api-int.sno-region1.example.com" | sudo tee -a /etc/hosts
    echo "192.168.130.10 console-openshift-console.apps.sno-region1.example.com" | sudo tee -a /etc/hosts
    echo "192.168.130.10 oauth-openshift.apps.sno-region1.example.com" | sudo tee -a /etc/hosts
fi

# Region 2 entries
if ! grep -q "api.sno-region2.example.com" /etc/hosts 2>/dev/null; then
    echo "192.168.131.10 api.sno-region2.example.com api-int.sno-region2.example.com" | sudo tee -a /etc/hosts
    echo "192.168.131.10 console-openshift-console.apps.sno-region2.example.com" | sudo tee -a /etc/hosts
    echo "192.168.131.10 oauth-openshift.apps.sno-region2.example.com" | sudo tee -a /etc/hosts
fi

echo "=== SNO prerequisites setup complete ==="
