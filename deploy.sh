#!/bin/bash
set -e

PROJECT_ID="${1:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${2:-us-central1}"
STAGING_BUCKET="gs://${PROJECT_ID}-adk-staging"

echo "============================================"
echo "  Nano Banana Pro Agent - Deploy"
echo "  Project: ${PROJECT_ID}"
echo "  Region:  ${REGION}"
echo "============================================"

# 1. Enable APIs
echo ""
echo ">>> [1/5] Enabling GCP APIs..."
gcloud services enable aiplatform.googleapis.com --project="${PROJECT_ID}" --quiet
gcloud services enable storage.googleapis.com --project="${PROJECT_ID}" --quiet
echo "    ✅ APIs enabled"

# 2. Create staging bucket
echo ""
echo ">>> [2/5] Ensuring staging bucket: ${STAGING_BUCKET}"
if gcloud storage buckets describe "${STAGING_BUCKET}" --project="${PROJECT_ID}" > /dev/null 2>&1; then
    echo "    ✅ Bucket exists"
else
    gcloud storage buckets create "${STAGING_BUCKET}" --project="${PROJECT_ID}" --location="${REGION}" --quiet
    echo "    ✅ Bucket created"
fi

# 3. Install dependencies
echo ""
echo ">>> [3/5] Installing Python dependencies..."
pip install --quiet "google-cloud-aiplatform[agent_engines,adk]>=1.112" "google-adk>=2.0" "google-auth" "requests" 2>&1 | tail -3
echo "    ✅ Dependencies installed"

# 4. Deploy agent
echo ""
echo ">>> [4/5] Deploying agent to Agent Engine..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

python3 - <<PYEOF
import os, sys
os.environ["GOOGLE_CLOUD_PROJECT"] = "${PROJECT_ID}"
os.environ["GOOGLE_CLOUD_LOCATION"] = "${REGION}"
os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "1"

sys.path.insert(0, "${SCRIPT_DIR}")

import vertexai
from vertexai.agent_engines import AdkApp

# Load agent via exec to avoid module import issues with cloudpickle
agent_globals = {"__name__": "__main__", "__file__": "${SCRIPT_DIR}/agent.py"}
with open("${SCRIPT_DIR}/agent.py") as f:
    exec(compile(f.read(), "${SCRIPT_DIR}/agent.py", "exec"), agent_globals)

root_agent = agent_globals["root_agent"]

client = vertexai.Client(project="${PROJECT_ID}", location="${REGION}")
app = AdkApp(agent=root_agent)

print("    Creating Agent Engine resource (this may take 2-5 minutes)...")
remote_agent = client.agent_engines.create(
    agent=app,
    config={
        "requirements": [
            "google-cloud-aiplatform[agent_engines,adk]>=1.112",
            "google-adk>=2.0",
            "google-auth",
            "requests",
        ],
        "staging_bucket": "${STAGING_BUCKET}",
    }
)

resource_name = remote_agent.api_resource.name
agent_id = resource_name.split("/")[-1]
print(f"    ✅ Agent deployed! ID: {agent_id}")
print(f"    Resource: {resource_name}")

with open("${SCRIPT_DIR}/.agent_id", "w") as f:
    f.write(agent_id)
PYEOF

# 5. Done
echo ""
echo "============================================"
echo "  ✅ Deployment complete!"
echo "  Agent ID saved to .agent_id"
echo "============================================"
