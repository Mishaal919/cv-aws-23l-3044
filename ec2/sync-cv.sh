#!/bin/bash
# sync-cv.sh - copy the site/ prefix of the CV bucket into the web root,
# replace {{HOSTED_ON}} with "EC2 <instance-id>", and log the result.
# Runs once from user data and then every 5 minutes from a systemd timer.
# Uses the instance role (no access keys).

BUCKET="cv-23l-3044"          # change if you added digits to the bucket name
PREFIX="site/"
STAGE="/opt/cv-site"          # raw copy of the bucket (placeholder intact)
WEBROOT="/var/www/html"
LOG="/var/log/cv-sync.log"

# IMDSv2: get a session token first, then read the metadata
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
