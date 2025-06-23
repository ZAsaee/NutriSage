#!/usr/bin/env bash
# =============================================================================
# NutriSage – bootstrap
# Creates: account budget, three versioned S3 buckets, and an .env file.
# =============================================================================
set -euo pipefail
PROJECT=nutrisage
AWS_REGION=${AWS_REGION:-us‑east‑1}        
AWS_PROFILE=${AWS_PROFILE:-default}

echo "Determining account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --profile "$AWS_PROFILE")
echo "   → $ACCOUNT_ID"

# --------------------------------------------------------------------------- #
# 1. Cost controls (Budgets + Cost Anomaly Detection)
# --------------------------------------------------------------------------- #
ALERT_EMAIL=${ALERT_EMAIL:-"z.s.asaee@gmail.com"} 

BUDGET_NAME="${PROJECT}-monthly"

if ! aws budgets describe-budget --account-id "$ACCOUNT_ID" \
       --budget-name "$BUDGET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
  echo "Creating a \$60 monthly budget with email alert..."

  # (A) Budget definition
  BUDGET_JSON=$(cat <<EOF
{
  "BudgetName": "$BUDGET_NAME",
  "BudgetType": "COST",
  "TimeUnit": "MONTHLY",
  "BudgetLimit": { "Amount": "60", "Unit": "USD" }
}
EOF
)

  # (B) Notification + subscriber list
  NOTIF_JSON=$(cat <<EOF
[{
  "Notification": {
    "NotificationType": "ACTUAL",
    "ComparisonOperator": "GREATER_THAN",
    "Threshold": 80,
    "ThresholdType": "PERCENTAGE"
  },
  "Subscribers": [{
    "SubscriptionType": "EMAIL",
    "Address": "$ALERT_EMAIL"
  }]
}]
EOF
)

  aws budgets create-budget \
        --account-id "$ACCOUNT_ID" \
        --budget "$BUDGET_JSON" \
        --notifications-with-subscribers "$NOTIF_JSON" \
        --profile "$AWS_PROFILE"
fi

# --------------------------------------------------------------------------- #
# Optional: Cost Anomaly Monitor (skip if perms missing)                      #
# --------------------------------------------------------------------------- #

{
  # Wrapping the entire stanza in a subshell keeps the main script alive
  # even if any CE command fails.
  set +e  # disable exit-on-error for this block only

  # Does the monitor already exist?
  aws ce get-anomaly-monitors --profile "$AWS_PROFILE" \
      --query 'AnomalyMonitors[?MonitorName==`'"${PROJECT}-anomaly"'`]' \
      --output text >/dev/null 2>&1
  MONITOR_EXISTS=$?

  if [[ $MONITOR_EXISTS -ne 0 ]]; then
    echo "🔎  Enabling Cost Anomaly Detection (best‑effort)…"
    aws ce create-anomaly-monitor --profile "$AWS_PROFILE" --anomaly-monitor '{
        "MonitorName": "'"${PROJECT}-anomaly"'",
        "MonitorType": "DIMENSIONAL",
        "MonitorDimension": "SERVICE"
    }' >/dev/null 2>&1
    [[ $? -eq 0 ]] && echo "   → Cost Anomaly Monitor created." \
                   || echo "   Skipped: insufficient IAM rights (harmless)."
  else
    echo "🔎  Anomaly monitor already exists – skipping."
  fi

  set -e  # re‑enable strict mode
}

# --------------------------------------------------------------------------- #
# 2. S3 buckets (raw, processed, models) – versioned, block public access
# --------------------------------------------------------------------------- #
for tier in raw processed models; do
  BUCKET_NAME="${PROJECT}-${tier}-${ACCOUNT_ID}"
  BUCKET_URI="s3://${BUCKET_NAME}"

  if ! aws s3api head-bucket --bucket "${BUCKET_NAME}" \
        --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "🪣  Creating bucket ${BUCKET_URI}"

    # us-east-1 is *special*: CreateBucketConfiguration must be omitted
    if [[ "${AWS_REGION}" == "us-east-1" ]]; then
      aws s3api create-bucket \
          --bucket "${BUCKET_NAME}" \
          --profile "$AWS_PROFILE"
    else
      aws s3api create-bucket \
          --bucket "${BUCKET_NAME}" \
          --create-bucket-configuration \
              LocationConstraint="${AWS_REGION}" \
          --profile "$AWS_PROFILE"
    fi

    # Security hardening (same for all regions)
    aws s3api put-public-access-block --bucket "${BUCKET_NAME}" \
        --public-access-block-configuration '{
            "BlockPublicAcls": true,
            "IgnorePublicAcls": true,
            "BlockPublicPolicy": true,
            "RestrictPublicBuckets": true
        }' --profile "$AWS_PROFILE"
    aws s3api put-bucket-versioning --bucket "${BUCKET_NAME}" \
        --versioning-configuration Status=Enabled \
        --profile "$AWS_PROFILE"
  else
    echo "🪣  Bucket ${BUCKET_URI} exists – skipping."
  fi
done

# --------------------------------------------------------------------------- #
# 3. .env file (used by CDK & local scripts)
# --------------------------------------------------------------------------- #
cat > .env <<EOF
# Auto‑generated
AWS_ACCOUNT_ID=$ACCOUNT_ID
AWS_REGION=$AWS_REGION
PROJECT=$PROJECT
RAW_BUCKET=${PROJECT}-raw-${ACCOUNT_ID}
PROCESSED_BUCKET=${PROJECT}-processed-${ACCOUNT_ID}
MODELS_BUCKET=${PROJECT}-models-${ACCOUNT_ID}
EOF

echo "bootstrap complete.  Review .env, commit, then run CDK."
