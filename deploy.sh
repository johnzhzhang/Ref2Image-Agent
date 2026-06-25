#!/bin/bash
set -e

# ============================================================
# Deploy ADK Image Generation Agent to Gemini Enterprise Agent Engine
# Usage: ./deploy.sh [PROJECT_ID] [REGION]
# ============================================================

PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${2:-us-central1}"
STAGING_BUCKET="gs://${PROJECT_ID}-adk-staging"

echo "============================================"
echo "  ADK Agent Deployment"
echo "  Project: ${PROJECT_ID}"
echo "  Region:  ${REGION}"
echo "============================================"

# 1. Enable required GCP APIs
echo ""
echo ">>> [1/5] Enabling GCP APIs..."
gcloud services enable aiplatform.googleapis.com --project="${PROJECT_ID}" --quiet
gcloud services enable storage.googleapis.com --project="${PROJECT_ID}" --quiet
echo "    ✅ APIs enabled"

# 2. Create staging bucket if not exists
echo ""
echo ">>> [2/5] Ensuring staging bucket: ${STAGING_BUCKET}"
if gcloud storage buckets describe "${STAGING_BUCKET}" --project="${PROJECT_ID}" > /dev/null 2>&1; then
    echo "    ✅ Bucket already exists"
else
    gcloud storage buckets create "${STAGING_BUCKET}" --project="${PROJECT_ID}" --location="${REGION}" --quiet
    echo "    ✅ Bucket created"
fi

# 3. Install Python dependencies
echo ""
echo ">>> [3/5] Installing Python dependencies..."
pip install --quiet --break-system-packages \
    "google-cloud-aiplatform[agent_engines,adk]>=1.112" \
    "google-adk>=2.0" \
    "requests" 2>&1 | tail -3
echo "    ✅ Dependencies installed"

# 4. Deploy agent to Agent Engine
echo ""
echo ">>> [4/5] Deploying agent to Agent Engine..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "${SCRIPT_DIR}/deploy_agent.py" \
    --project="${PROJECT_ID}" \
    --region="${REGION}" \
    --staging-bucket="${STAGING_BUCKET}"

# 5. Done
echo ""
echo "============================================"
echo "  ✅ Deployment complete!"
echo "  Run: python3 deploy_agent.py --project=${PROJECT_ID} --region=${REGION} --test"
echo "  to test the deployed agent."
echo "============================================"
