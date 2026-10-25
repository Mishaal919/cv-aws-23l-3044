#!/bin/bash
# user-data.sh - EC2 launch script (Amazon Linux 2023)
# 1. install and start Apache  2. install sync-cv.sh  3. schedule it every
# 5 minutes with a systemd timer  4. run it once now.
# No access keys: the AWS CLI uses the attached role cv-ec2-role-23l-3044.

dnf install -y httpd
systemctl enable --now httpd

# --- sync script (same content as ec2/sync-cv.sh in the repo) ---
cat > /usr/local/bin/sync-cv.sh <<'EOF'
#!/bin/bash
BUCKET="cv-23l-3044"          # change if you added digits to the bucket name
PREFIX="site/"
STAGE="/opt/cv-site"
WEBROOT="/var/www/html"
LOG="/var/log/cv-sync.log"

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
        -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
        http://169.254.169.254/latest/meta-data/placement/region)

mkdir -p "$STAGE" "$WEBROOT"

if aws s3 sync "s3://$BUCKET/$PREFIX" "$STAGE/" --delete --region "$REGION" >/dev/null 2>&1 \
   && [ -f "$STAGE/index.html" ]; then
  cp "$STAGE/style.css" "$STAGE/cv.pdf" "$WEBROOT/"
  sed "s/{{HOSTED_ON}}/EC2 $INSTANCE_ID/" "$STAGE/index.html" > "$WEBROOT/index.html.tmp" \
    && mv "$WEBROOT/index.html.tmp" "$WEBROOT/index.html"
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) OK   sync s3://$BUCKET/$PREFIX -> $WEBROOT ($INSTANCE_ID)" >> "$LOG"
else
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) FAIL sync s3://$BUCKET/$PREFIX ($INSTANCE_ID)" >> "$LOG"
  exit 1
fi
EOF
chmod +x /usr/local/bin/sync-cv.sh

# --- systemd service + timer: run every 5 minutes ---
cat > /etc/systemd/system/cv-sync.service <<'EOF'
[Unit]
Description=Sync CV from S3 into the web root
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-cv.sh
EOF

cat > /etc/systemd/system/cv-sync.timer <<'EOF'
[Unit]
Description=Run cv-sync every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=10s

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now cv-sync.timer

# --- run once now ---
/usr/local/bin/sync-cv.sh
