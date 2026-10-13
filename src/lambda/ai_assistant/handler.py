"""ai_assistant: an enterprise AI assistant for machinery/maintenance
documentation that is permission-aware via SSO.

For every request it:

1. resolves the caller's identity and group membership by calling
   "Manage access and single sign-on" (represented here by IAM groups,
   queried through `iam:ListGroupsForUser` -- the same call pattern used to
   resolve a federated SSO user's groups in a real deployment);
2. ingests/searches the "Data sources": the S3 document bucket (`general/`
   prefix), the FSx machinery/processes documentation (mirrored into the
   `machinery/` prefix -- see the note in main.tf about why EFS stands in for
   FSx on the local emulator), and the third-party enterprise
   applications/document repository connector (`partner-connector/` prefix);
3. keeps only the documents the caller's groups are allowed to see, performs
   a simple Kendra-style keyword retrieval over them, and (optionally)
   calls Bedrock to generate a final, permission-filtered answer.
"""
import json
import os

import boto3
from botocore.exceptions import ClientError

REGION = os.environ.get("REGION", "us-east-1")
DOCUMENT_BUCKET = os.environ["DOCUMENT_BUCKET"]
GENERATION_MODEL_ID = os.environ.get("GENERATION_MODEL_ID", "anthropic.claude-3-haiku-20240307-v1:0")

_ENDPOINT_KWARGS = {
    "endpoint_url": "http://localhost:4566",
    "aws_access_key_id": "test",
    "aws_secret_access_key": "test",
}

iam = boto3.client("iam", region_name=REGION, **_ENDPOINT_KWARGS)
s3 = boto3.client("s3", region_name=REGION, **_ENDPOINT_KWARGS)
bedrock_runtime = boto3.client("bedrock-runtime", region_name=REGION, **_ENDPOINT_KWARGS)

# Maps each "Data source" to the IAM group (SSO group) allowed to see it.
# A user with no matching group for a prefix never sees that data source's
# content, regardless of what the keyword search would otherwise retrieve.
DATA_SOURCE_PREFIXES = {
    "general/": None,  # visible to every authenticated user
    "machinery/": "maintenance-engineers",  # FSx-mirrored machinery/process docs
    "partner-connector/": "maintenance-engineers",  # third-party connector content
}


def lambda_handler(event, context):
    username = (event or {}).get("user")
    query = (event or {}).get("query")

    if not username or not query:
        return {"error": "'user' and 'query' are required."}

    groups = _resolve_user_groups(username)
    allowed_prefixes = _allowed_prefixes(groups)

    matches = _search_data_sources(query, allowed_prefixes)
    answer = _generate_answer(query, matches)

    return {
        "user": username,
        "groups": groups,
        "allowed_data_sources": allowed_prefixes,
        "answer": answer,
        "sources": [match["key"] for match in matches],
    }


def _resolve_user_groups(username):
    """Step 1: ask "Manage access and single sign-on" for the caller's groups."""
    try:
        response = iam.list_groups_for_user(UserName=username)
        return [group["GroupName"] for group in response.get("Groups", [])]
    except ClientError:
        # Unknown/unprovisioned user: treat as having no elevated group access.
        return []


def _allowed_prefixes(groups):
    """Translate the caller's groups into the set of data-source prefixes
    they are entitled to search."""
    allowed = []
    for prefix, required_group in DATA_SOURCE_PREFIXES.items():
        if required_group is None or any(required_group in group for group in groups):
            allowed.append(prefix)
    return allowed


def _search_data_sources(query, allowed_prefixes):
    """Step 2: ingest/search the data sources (S3 bucket, FSx-mirrored
    machinery docs, third-party connector content), restricted to the
    prefixes the caller is allowed to read."""
    terms = [term.lower() for term in query.split() if term]
    matches = []

    for prefix in allowed_prefixes:
        try:
            listing = s3.list_objects_v2(Bucket=DOCUMENT_BUCKET, Prefix=prefix)
        except ClientError:
            continue

        for obj in listing.get("Contents", []):
            key = obj["Key"]
            if key.endswith("/"):
                continue
            try:
                body = s3.get_object(Bucket=DOCUMENT_BUCKET, Key=key)["Body"].read().decode("utf-8", "ignore")
            except ClientError:
                continue

            if not terms or any(term in body.lower() for term in terms):
                matches.append({"key": key, "text": body})

    return matches


def _generate_answer(query, matches):
    """Step 3: generate a grounded, permission-filtered answer from only the
    documents the caller was allowed to retrieve."""
    if not matches:
        return "No documents in your permitted data sources matched this query."

    context = "\n\n".join(f"[{match['key']}]\n{match['text']}" for match in matches)

    prompt = (
        "Answer the question using only the context below, which has already "
        "been filtered to documents the user is permitted to see. "
        "If the answer isn't in the context, say you don't know.\n\n"
        f"Context:\n{context}\n\nQuestion: {query}"
    )

    body = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 512,
        "messages": [{"role": "user", "content": prompt}],
    })

    try:
        response = bedrock_runtime.invoke_model(
            modelId=GENERATION_MODEL_ID,
            body=body,
            contentType="application/json",
            accept="application/json",
        )
        payload = json.loads(response["body"].read())
        content = payload.get("content", [])
        if content:
            return content[0]["text"]
    except ClientError:
        pass

    # Fallback when Bedrock generation is unavailable: return the retrieved
    # passages directly so the assistant still answers from permitted data.
    return "\n\n".join(match["text"] for match in matches)
