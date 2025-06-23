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
BUDGET_NAME="${PROJECT}-monthly"
if ! aws budgets describe-budget --account-id "$ACCOUNT_ID" \
       --budget-name "$BUDGET_NAME" --profile "$AWS_PROFILE" 2>/dev/null; then
  echo "Creating a \$60 monthly budget with email alert..."
  aws budgets create-budget --account-id "$ACCOUNT_ID" \
    --budget '{
      "BudgetName":"'"$BUDGET_NAME"'",
      "BudgetLimit":{"Amount":"60","Unit":"USD"},
      "TimeUnit":"MONTHLY",
      "BudgetType":"COST",
      "CostFilters":{},
      "CostTypes":{"IncludeCredit":false},
      "Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN",
                      "Threshold":80,"ThresholdType":"PERCENTAGE"},
      "Subscribers":[{"SubscriptionType":"EMAIL","Address":"z.s.asaee@gmail.com"}]
    }' --profile "$AWS_PROFILE"
fi

if ! aws ce get-anomaly-monitors --profile "$AWS_PROFILE" \
      | grep -q "${PROJECT}-anomaly"; then
  echo "Enabling Cost Anomaly Detection..."
  aws ce create-anomaly-monitor --monitor-name "${PROJECT}-anomaly" \
      --monitor-type DIMENSIONAL --monitor-dimension SERVICE \
      --profile "$AWS_PROFILE" >/dev/null
fi

# --------------------------------------------------------------------------- #
# 2. S3 buckets (raw, processed, models) – versioned, block public access
# --------------------------------------------------------------------------- #
for tier in raw processed models; do
  BUCKET="s3://${PROJECT}-${tier}-${ACCOUNT_ID}"
  if ! aws s3api head-bucket --bucket "${PROJECT}-${tier}-${ACCOUNT_ID}" \
        --profile "$AWS_PROFILE" 2>/dev/null; then
    echo "🪣  Creating bucket ${BUCKET}"
    aws s3api create-bucket --bucket "${PROJECT}-${tier}-${ACCOUNT_ID}" \
      --create-bucket-configuration LocationConstraint="$AWS_REGION" \
      --profile "$AWS_PROFILE"
    aws s3api put-public-access-block --bucket "${PROJECT}-${tier}-${ACCOUNT_ID}" \
      --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,\
BlockPublicPolicy=true,RestrictPublicBuckets=true --profile "$AWS_PROFILE"
    aws s3api put-bucket-versioning --bucket "${PROJECT}-${tier}-${ACCOUNT_ID}" \
      --versioning-configuration Status=Enabled --profile "$AWS_PROFILE"
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
