"""
Deploy the ADK Image Generation Agent to Gemini Enterprise Agent Engine.
Can also test a deployed agent.

Usage:
  python3 deploy_agent.py --project=PROJECT --region=REGION --staging-bucket=gs://BUCKET
  python3 deploy_agent.py --project=PROJECT --region=REGION --test
"""
import argparse, asyncio, sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def deploy(project: str, region: str, staging_bucket: str):
    """Deploy agent to Agent Engine.
    
    To avoid 'No module named image_gen_agent' on Agent Engine,
    we define the agent inline here rather than importing from a package.
    Cloudpickle will capture all the closures and functions directly.
    """
    import vertexai
    from vertexai.agent_engines import AdkApp
    from google.adk.agents import Agent
    from google.adk.agents.callback_context import CallbackContext
    from google.adk.tools.tool_context import ToolContext
    from google.adk.tools.preload_memory_tool import PreloadMemoryTool
    import google.genai.types as types

    # --- Inline agent definition (same as image_gen_agent/agent.py) ---
    agent_dir = os.path.dirname(os.path.abspath(__file__))
    if agent_dir not in sys.path:
        sys.path.insert(0, agent_dir)

    # Execute agent.py in current namespace to get root_agent
    agent_file = os.path.join(agent_dir, "image_gen_agent", "agent.py")
    agent_globals = {"__name__": "__main__", "__file__": agent_file}
    with open(agent_file) as f:
        exec(compile(f.read(), agent_file, "exec"), agent_globals)

    root_agent = agent_globals["root_agent"]

    print(f"    Initializing Vertex AI client (project={project}, location={region})...")
    client = vertexai.Client(project=project, location=region)

    print(f"    Wrapping agent in AdkApp...")
    app = AdkApp(agent=root_agent)

    print(f"    Creating Agent Engine resource (this may take 2-5 minutes)...")
    remote_agent = client.agent_engines.create(
        agent=app,
        config={
            "requirements": [
                "google-cloud-aiplatform[agent_engines,adk]>=1.112",
                "google-adk>=2.0",
                "google-auth",
                "requests",
            ],
            "staging_bucket": staging_bucket,
        }
    )

    resource_name = remote_agent.api_resource.name
    agent_id = resource_name.split("/")[-1]

    print(f"    ✅ Agent deployed!")
    print(f"    Resource: {resource_name}")
    print(f"    Agent ID: {agent_id}")

    # Save agent ID for later use
    with open(os.path.join(os.path.dirname(__file__), ".agent_id"), "w") as f:
        f.write(agent_id)

    return remote_agent


def test(project: str, region: str):
    """Test a deployed agent."""
    import vertexai

    # Load agent ID
    id_file = os.path.join(os.path.dirname(__file__), ".agent_id")
    if not os.path.exists(id_file):
        print("    ❌ No .agent_id file found. Deploy first.")
        sys.exit(1)

    agent_id = open(id_file).read().strip()
    print(f"    Testing agent: {agent_id}")

    client = vertexai.Client(project=project, location=region)
    resource_name = f"projects/{project}/locations/{region}/reasoningEngines/{agent_id}"
    remote_agent = client.agent_engines.get(name=resource_name)

    async def run_test():
        print("    Sending test query...")
        async for event in remote_agent.async_stream_query(
            user_id="deploy_test",
            message="你好，请介绍一下你的功能",
        ):
            if hasattr(event, 'content') and event.content:
                for part in event.content.parts:
                    if hasattr(part, 'text') and part.text:
                        print(f"    Agent: {part.text[:200]}")

    asyncio.run(run_test())
    print("    ✅ Test passed!")


def delete(project: str, region: str):
    """Delete a deployed agent."""
    import vertexai

    id_file = os.path.join(os.path.dirname(__file__), ".agent_id")
    if not os.path.exists(id_file):
        print("    ❌ No .agent_id file found.")
        sys.exit(1)

    agent_id = open(id_file).read().strip()
    print(f"    Deleting agent: {agent_id}")

    client = vertexai.Client(project=project, location=region)
    resource_name = f"projects/{project}/locations/{region}/reasoningEngines/{agent_id}"
    remote_agent = client.agent_engines.get(name=resource_name)
    remote_agent.delete(force=True)

    os.remove(id_file)
    print("    ✅ Agent deleted!")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Deploy/test ADK agent to Agent Engine")
    parser.add_argument("--project", required=True)
    parser.add_argument("--region", default="us-central1")
    parser.add_argument("--staging-bucket", default=None)
    parser.add_argument("--test", action="store_true", help="Test deployed agent")
    parser.add_argument("--delete", action="store_true", help="Delete deployed agent")
    args = parser.parse_args()

    os.environ["GOOGLE_CLOUD_PROJECT"] = args.project
    os.environ["GOOGLE_CLOUD_LOCATION"] = args.region
    os.environ["GOOGLE_GENAI_USE_VERTEXAI"] = "1"

    if args.test:
        test(args.project, args.region)
    elif args.delete:
        delete(args.project, args.region)
    else:
        if not args.staging_bucket:
            args.staging_bucket = f"gs://{args.project}-adk-staging"
        deploy(args.project, args.region, args.staging_bucket)
