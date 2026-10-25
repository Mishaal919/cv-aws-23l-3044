#!/bin/bash
# collect-evidence.sh - gather evidence for the CV-on-AWS lab into evidence.txt
# Usage: ./collect-evidence.sh <bucket-name> <ec2-address> <lambda-address>
# Run it where the AWS CLI has credentials for the account (e.g. AWS CloudShell).

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <bucket-name> <ec2-address> <lambda-address>"
  exit 1
fi

BUCKET="$1"
EC2_URL="${2%/}"
LAMBDA_URL="${3%/}"
# accept addresses with or without http(s)://
case "$EC2_URL" in http*) ;; *) EC2_URL="http://$EC2_URL" ;; esac
case "$LAMBDA_URL" in http*) ;; *) LAMBDA_URL="https://$LAMBDA_URL" ;; esac

ROLL="23l-3044"
EC2_ROLE="cv-ec2-role-$ROLL"
LAMBDA_ROLE="cv-lambda-role-$ROLL"
FUNC="cv-func-$ROLL"
INSTANCE_NAME="cv-ec2-$ROLL"
LOG_GROUP="/aws/lambda/$FUNC"
OUT="evidence.txt"

: > "$OUT"

section() { printf '\n== %s ==\n' "$1" >> "$OUT"; }

# run a command; on failure note it in the section and carry on
run() {
  if ! "$@" >> "$OUT" 2>&1; then
    echo "COMMAND FAILED: $*" >> "$OUT"
  fi
}

echo "Evidence generated $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUT"

section "caller"
run aws sts get-caller-identity --output table

section "public-access"
run aws s3api get-public-access-block --bucket "$BUCKET" --output table

section "versioning"
run aws s3api get-bucket-versioning --bucket "$BUCKET" --output table

section "objects"
run aws s3 ls "s3://$BUCKET/site/" --recursive --human-readable --summarize

section "ec2-policy"
POLICY_NAMES=$(aws iam list-role-policies --role-name "$EC2_ROLE" --query 'PolicyNames' --output text 2>>"$OUT")
if [ -z "$POLICY_NAMES" ]; then
  echo "COMMAND FAILED: no inline policy found on $EC2_ROLE" >> "$OUT"
fi
for P in $POLICY_NAMES; do
  run aws iam get-role-policy --role-name "$EC2_ROLE" --policy-name "$P" --output json
done

section "lambda-policy"
echo "-- managed policies --" >> "$OUT"
run aws iam list-attached-role-policies --role-name "$LAMBDA_ROLE" --output table
echo "-- inline policies --" >> "$OUT"
POLICY_NAMES=$(aws iam list-role-policies --role-name "$LAMBDA_ROLE" --query 'PolicyNames' --output text 2>>"$OUT")
if [ -z "$POLICY_NAMES" ]; then
  echo "COMMAND FAILED: no inline policy found on $LAMBDA_ROLE" >> "$OUT"
fi
for P in $POLICY_NAMES; do
  run aws iam get-role-policy --role-name "$LAMBDA_ROLE" --policy-name "$P" --output json
done

INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=$INSTANCE_NAME" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)
SG_IDS=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text 2>/dev/null)

section "security-group"
if [ -n "$SG_IDS" ] && [ "$SG_IDS" != "None" ]; then
  run aws ec2 describe-security-groups --group-ids $SG_IDS \
    --query 'SecurityGroups[].{GroupId:GroupId,Name:GroupName,Inbound:IpPermissions[].{Proto:IpProtocol,From:FromPort,To:ToPort,IPv4:IpRanges[].CidrIp,IPv6:Ipv6Ranges[].CidrIpv6,PrefixLists:PrefixListIds[].PrefixListId}}' \
    --output json
else
  echo "COMMAND FAILED: could not find the security group of $INSTANCE_NAME" >> "$OUT"
fi

section "instance"
run aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType,State:State.Name,PublicIp:PublicIpAddress,HttpTokens:MetadataOptions.HttpTokens,InstanceProfile:IamInstanceProfile.Arn}' \
  --output table

section "endpoints"
REGION=$(aws s3api get-bucket-location --bucket "$BUCKET" --query LocationConstraint --output text 2>/dev/null)
[ -z "$REGION" ] || [ "$REGION" = "None" ] && REGION="us-east-1"
S3_URL="https://$BUCKET.s3.$REGION.amazonaws.com/site/index.html"
for URL in "$EC2_URL/" "$EC2_URL/style.css" "$EC2_URL/cv.pdf" \
           "$LAMBDA_URL/" "$LAMBDA_URL/style.css" "$LAMBDA_URL/cv.pdf" "$LAMBDA_URL/anything" \
           "$S3_URL"; do
  RESULT=$(curl -s -o /dev/null --max-time 15 -w '%{http_code} %{content_type}' "$URL")
  if [ $? -ne 0 ] && [ -z "$RESULT" ]; then RESULT="COMMAND FAILED: curl"; fi
  echo "$URL -> $RESULT" >> "$OUT"
done

section "lambda-logs"
if LOGS=$(aws logs tail "$LOG_GROUP" --since 1d --format short 2>&1); then
  echo "$LOGS" | tail -n 15 >> "$OUT"
else
  echo "$LOGS" >> "$OUT"
  echo "COMMAND FAILED: aws logs tail $LOG_GROUP" >> "$OUT"
fi

section "log-retention"
run aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" \
  --query 'logGroups[].{LogGroup:logGroupName,RetentionDays:retentionInDays}' --output table

echo "DONE"
