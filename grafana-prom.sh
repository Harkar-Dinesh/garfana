#!/bin/bash

set -e

echo "=================================================="
echo " Installing Prometheus + Grafana + Alertmanager"
echo " + Node Exporter"
echo " Amazon Linux 2023"
echo "=================================================="

# ============================================================
# 1. Update System
# ============================================================

sudo dnf update -y

# curl is already installed on Amazon Linux 2023.
# wget is not required because this script uses curl.
sudo dnf install -y \
    tar \
    gzip \
    ca-certificates \
    shadow-utils

echo "Required packages installed."


# ============================================================
# 2. Create Prometheus User and Directories
# ============================================================

sudo useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true

sudo mkdir -p /etc/prometheus
sudo mkdir -p /var/lib/prometheus

sudo chown prometheus:prometheus /etc/prometheus
sudo chown prometheus:prometheus /var/lib/prometheus

echo "Prometheus user and directories created."


# ============================================================
# 3. Install Prometheus
# ============================================================

cd /tmp

sudo rm -rf prometheus-2.55.1.linux-amd64
sudo rm -f prometheus-2.55.1.linux-amd64.tar.gz

curl -LO https://github.com/prometheus/prometheus/releases/download/v2.55.1/prometheus-2.55.1.linux-amd64.tar.gz

tar -xzf prometheus-2.55.1.linux-amd64.tar.gz

cd prometheus-2.55.1.linux-amd64

sudo cp prometheus /usr/local/bin/
sudo cp promtool /usr/local/bin/

sudo chown prometheus:prometheus /usr/local/bin/prometheus
sudo chown prometheus:prometheus /usr/local/bin/promtool

sudo cp -r consoles /etc/prometheus/
sudo cp -r console_libraries /etc/prometheus/

sudo chown -R prometheus:prometheus /etc/prometheus

echo "Prometheus installed."


# ============================================================
# 4. Install Grafana
# ============================================================

sudo tee /etc/yum.repos.d/grafana.repo > /dev/null <<'EOF'
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
EOF

sudo dnf makecache

sudo dnf install -y grafana

echo "Grafana installed."


# ============================================================
# 5. Install Alertmanager
# ============================================================

cd /tmp

sudo rm -rf alertmanager-0.27.0.linux-amd64
sudo rm -f alertmanager-0.27.0.linux-amd64.tar.gz

curl -LO https://github.com/prometheus/alertmanager/releases/download/v0.27.0/alertmanager-0.27.0.linux-amd64.tar.gz

tar -xzf alertmanager-0.27.0.linux-amd64.tar.gz

cd alertmanager-0.27.0.linux-amd64

sudo cp alertmanager /usr/local/bin/
sudo cp amtool /usr/local/bin/

sudo mkdir -p /etc/alertmanager
sudo mkdir -p /var/lib/alertmanager

sudo cp alertmanager.yml /etc/alertmanager/

sudo chown -R prometheus:prometheus /etc/alertmanager
sudo chown -R prometheus:prometheus /var/lib/alertmanager

echo "Alertmanager installed."


# ============================================================
# 6. Install Node Exporter
# ============================================================

sudo useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true

cd /tmp

sudo rm -rf node_exporter-1.8.2.linux-amd64
sudo rm -f node_exporter-1.8.2.linux-amd64.tar.gz

curl -LO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz

tar -xzf node_exporter-1.8.2.linux-amd64.tar.gz

cd node_exporter-1.8.2.linux-amd64

sudo cp node_exporter /usr/local/bin/

sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

echo "Node Exporter installed."


# ============================================================
# 7. Prometheus Alert Rules
# ============================================================

sudo tee /etc/prometheus/alert.rules.yml > /dev/null <<'EOF'
groups:

  - name: example-alerts

    rules:

      # ------------------------------------------------------
      # Instance Down
      # ------------------------------------------------------

      - alert: InstanceDown
        expr: up == 0
        for: 1m

        labels:
          severity: critical

        annotations:
          summary: "Instance {{ $labels.instance }} is down"
          description: "Prometheus target {{ $labels.instance }} has been unreachable for more than 1 minute."


      # ------------------------------------------------------
      # High CPU Usage
      # ------------------------------------------------------

      - alert: HighCPUUsage
        expr: 100 - (avg by(instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 40
        for: 2m

        labels:
          severity: critical

        annotations:
          summary: "High CPU usage detected on {{ $labels.instance }}"
          description: "CPU usage > 40% for more than 2 minutes. VALUE = {{ $value }}%"


      # ------------------------------------------------------
      # Unauthorized Requests
      # ------------------------------------------------------

      - alert: UnauthorizedRequests
        expr: increase(http_requests_total{status=~"401|403"}[5m]) > 0
        for: 1m

        labels:
          severity: warning

        annotations:
          summary: "Unauthorized requests on {{ $labels.instance }}"
          description: "Detected unauthorized (401/403) requests in the past 5 minutes."


      # ------------------------------------------------------
      # High Disk Usage
      # ------------------------------------------------------

      - alert: HighDiskUsage
        expr: (1 - (node_filesystem_avail_bytes{fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{fstype!~"tmpfs|overlay"})) * 100 > 80
        for: 2m

        labels:
          severity: warning

        annotations:
          summary: "High Disk Usage on {{ $labels.instance }}"
          description: "Disk usage is above 80% for more than 2 minutes. VALUE = {{ $value }}%"
EOF

sudo chown prometheus:prometheus /etc/prometheus/alert.rules.yml


# ============================================================
# 8. Alertmanager + PagerDuty Configuration
# ============================================================

sudo tee /etc/alertmanager/alertmanager.yml > /dev/null <<'EOF'
route:
  receiver: pagerduty

  group_wait: 10s
  group_interval: 10s
  repeat_interval: 1h

receivers:

  - name: pagerduty

    pagerduty_configs:

      - routing_key: "fea70865f5da460bc0ea973f565929ce"
        severity: "critical"
EOF

sudo chown prometheus:prometheus /etc/alertmanager/alertmanager.yml


# ============================================================
# 9. Prometheus Configuration
# ============================================================

sudo tee /etc/prometheus/prometheus.yml > /dev/null <<'EOF'

global:

  scrape_interval: 15s
  evaluation_interval: 15s


# ==========================================================
# Alertmanager
# ==========================================================

alerting:

  alertmanagers:

    - static_configs:

        - targets:
            - "localhost:9093"


# ==========================================================
# Alert Rules
# ==========================================================

rule_files:

  - "/etc/prometheus/alert.rules.yml"


# ==========================================================
# Monitor Node Exporter on Prometheus Server
# ==========================================================

scrape_configs:

  - job_name: "prometheus"

    static_configs:

      - targets:
          - "localhost:9100"


# ==========================================================
# Discover EC2 Node Exporters
# ==========================================================

  - job_name: "ec2-node-exporters"

    ec2_sd_configs:

      - region: us-east-1

        port: 9100

        filters:

          - name: "tag:Name"

            values:
              - "node-server"


    relabel_configs:

      - source_labels:
          - __meta_ec2_private_ip

        regex: (.*)

        target_label: __address__

        replacement: "$1:9100"

EOF

sudo chown prometheus:prometheus /etc/prometheus/prometheus.yml


# ============================================================
# 10. Validate Prometheus Configuration
# ============================================================

echo ""
echo "=================================================="
echo " Checking Prometheus Configuration"
echo "=================================================="

sudo -u prometheus /usr/local/bin/promtool check config \
    /etc/prometheus/prometheus.yml

echo "Prometheus configuration is valid."


# ============================================================
# 11. Prometheus Systemd Service
# ============================================================

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus

ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

Restart=always

[Install]
WantedBy=multi-user.target
EOF


# ============================================================
# 12. Alertmanager Systemd Service
# ============================================================

sudo tee /etc/systemd/system/alertmanager.service > /dev/null <<'EOF'
[Unit]
Description=Alertmanager
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus

ExecStart=/usr/local/bin/alertmanager \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/var/lib/alertmanager/

Restart=always

[Install]
WantedBy=multi-user.target
EOF


# ============================================================
# 13. Node Exporter Systemd Service
# ============================================================

sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter

ExecStart=/usr/local/bin/node_exporter

Restart=always

[Install]
WantedBy=multi-user.target
EOF


# ============================================================
# 14. Reload Systemd
# ============================================================

sudo systemctl daemon-reload


# ============================================================
# 15. Enable and Start Services
# ============================================================

sudo systemctl enable --now prometheus
sudo systemctl enable --now alertmanager
sudo systemctl enable --now grafana-server
sudo systemctl enable --now node_exporter


# ============================================================
# 16. Check Service Status
# ============================================================

echo ""
echo "=================================================="
echo " Service Status"
echo "=================================================="

sudo systemctl --no-pager status prometheus
echo ""

sudo systemctl --no-pager status alertmanager
echo ""

sudo systemctl --no-pager status grafana-server
echo ""

sudo systemctl --no-pager status node_exporter


# ============================================================
# 17. Check Listening Ports
# ============================================================

echo ""
echo "=================================================="
echo " Listening Ports"
echo "=================================================="

sudo ss -tulpn | grep -E ':9090|:3000|:9093|:9100' || true


# ============================================================
# 18. Final Output
# ============================================================

echo ""
echo "=================================================="
echo " Installation Completed"
echo "=================================================="

echo ""
echo "Prometheus   : http://SERVER-IP:9090"
echo "Grafana      : http://SERVER-IP:3000"
echo "Alertmanager : http://SERVER-IP:9093"
echo "Node Exporter: http://SERVER-IP:9100"

echo ""
echo "=================================================="
echo " IMPORTANT"
echo "=================================================="

echo ""
echo "Prometheus EC2 instance needs IAM permissions:"
echo "  ec2:DescribeInstances"
echo "  ec2:DescribeTags"

echo ""
echo "Node Exporter security group must allow:"
echo "  TCP 9100 from Prometheus server/security group"

echo ""
echo "Prometheus security group:"
echo "  TCP 9090 from your administration/client IP"

echo ""
echo "Grafana security group:"
echo "  TCP 3000 from your administration/client IP"

echo ""
echo "Alertmanager security group:"
echo "  TCP 9093 from your administration/client IP"

echo ""
echo "=================================================="
echo " Done"
echo "=================================================="
