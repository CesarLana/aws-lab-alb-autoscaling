#!/bin/bash
# ==============================================================================
# AWS Lab: ALB + Auto Scaling Group
# Script: scripts/user_data.sh
# Purpose: Initialize Apache HTTP Server on Amazon Linux 2023 with dynamic
#          metadata display (IMDSv2) for ALB balancing and scaling validation.
# ==============================================================================

set -euo pipefail

# Update packages and install Apache HTTP server
dnf update -y
dnf install -y httpd

# Start and enable Apache service
systemctl start httpd
systemctl enable httpd

# Retrieve metadata securely using IMDSv2 (Session Token required)
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-id || echo "Unknown")
AVAILABILITY_ZONE=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone || echo "Unknown")
INSTANCE_TYPE=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/instance-type || echo "Unknown")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4 || echo "Unknown")
AMI_ID=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" http://169.254.169.254/latest/meta-data/ami-id || echo "Unknown")

# Create a modern, responsive HTML page to visually verify multi-AZ load balancing
cat <<EOF > /var/www/html/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AWS High Availability Demo | ALB & Auto Scaling</title>
  <style>
    :root {
      --aws-orange: #FF9900;
      --aws-squid: #232F3E;
      --aws-bg: #0F172A;
      --card-bg: #1E293B;
      --text-main: #F8FAFC;
      --text-muted: #94A3B8;
      --green: #10B981;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background-color: var(--aws-bg);
      color: var(--text-main);
      display: flex;
      justify-content: center;
      align-items: center;
      min-height: 100vh;
      padding: 1.5rem;
    }
    .card {
      background: var(--card-bg);
      border: 1px solid rgba(255, 153, 0, 0.25);
      border-radius: 1rem;
      padding: 2.5rem;
      max-width: 600px;
      width: 100%;
      box-shadow: 0 20px 40px -15px rgba(0,0,0,0.5);
    }
    .header {
      display: flex;
      align-items: center;
      gap: 1rem;
      margin-bottom: 2rem;
      border-bottom: 1px solid rgba(255, 255, 255, 0.1);
      padding-bottom: 1.5rem;
    }
    .badge-status {
      display: inline-flex;
      align-items: center;
      gap: 0.5rem;
      background: rgba(16, 185, 129, 0.15);
      color: var(--green);
      padding: 0.35rem 0.75rem;
      border-radius: 9999px;
      font-size: 0.875rem;
      font-weight: 600;
    }
    .dot {
      width: 8px;
      height: 8px;
      background-color: var(--green);
      border-radius: 50%;
      box-shadow: 0 0 10px var(--green);
      animation: pulse 1.5s infinite;
    }
    @keyframes pulse {
      0%, 100% { opacity: 1; transform: scale(1); }
      50% { opacity: 0.4; transform: scale(1.2); }
    }
    h1 {
      font-size: 1.5rem;
      font-weight: 700;
      color: var(--text-main);
    }
    .subtitle {
      color: var(--text-muted);
      font-size: 0.875rem;
      margin-top: 0.25rem;
    }
    .meta-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 1rem;
      margin-bottom: 2rem;
    }
    .meta-item {
      background: rgba(15, 23, 42, 0.6);
      padding: 1rem;
      border-radius: 0.5rem;
      border: 1px solid rgba(255,255,255,0.05);
    }
    .meta-label {
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: var(--aws-orange);
      font-weight: 600;
      margin-bottom: 0.25rem;
    }
    .meta-value {
      font-size: 1.1rem;
      font-weight: 600;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      color: #FFFFFF;
      word-break: break-all;
    }
    .footer {
      font-size: 0.8rem;
      color: var(--text-muted);
      text-align: center;
      padding-top: 1rem;
      border-top: 1px solid rgba(255, 255, 255, 0.1);
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div style="flex: 1;">
        <h1>AWS Multi-AZ Target</h1>
        <p class="subtitle">Application Load Balancer & Auto Scaling Lab</p>
      </div>
      <div class="badge-status">
        <span class="dot"></span>
        HEALTHY
      </div>
    </div>

    <div class="meta-grid">
      <div class="meta-item">
        <div class="meta-label">Availability Zone</div>
        <div class="meta-value">$AVAILABILITY_ZONE</div>
      </div>
      <div class="meta-item">
        <div class="meta-label">Instance ID</div>
        <div class="meta-value">$INSTANCE_ID</div>
      </div>
      <div class="meta-item">
        <div class="meta-label">Private IPv4</div>
        <div class="meta-value">$PRIVATE_IP</div>
      </div>
      <div class="meta-item">
        <div class="meta-label">Instance Type</div>
        <div class="meta-value">$INSTANCE_TYPE</div>
      </div>
    </div>

    <div class="footer">
      Generated automatically via Amazon Linux 2023 User Data (IMDSv2)
    </div>
  </div>
</body>
</html>
EOF

# Health check dedicated endpoint for target groups
cat <<EOF > /var/www/html/healthz
OK
EOF

chmod 644 /var/www/html/index.html /var/www/html/healthz
