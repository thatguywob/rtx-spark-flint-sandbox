import urllib.request
import urllib.error
import json
import time
import os
import sys

URL = os.environ.get("FLINT_API_URL", "http://127.0.0.1:8080/v1/chat/completions")
API_KEY = os.environ.get("FLINT_API_KEY", "")

# 1. Verification of Authentication Enforcement (Security Gate)
print(f"[1/2] Probing unauthenticated access rejection at {URL}...")
unauth_payload = {
    "model": "flint",
    "messages": [{"role": "user", "content": "Ping"}]
}
unauth_req = urllib.request.Request(
    URL,
    data=json.dumps(unauth_payload).encode("utf-8"),
    headers={"Content-Type": "application/json"}
)

try:
    with urllib.request.urlopen(unauth_req, timeout=10) as resp:
        print("SECURITY FAILURE: Endpoint accepted unauthenticated request!", file=sys.stderr)
        sys.exit(1)
except urllib.error.HTTPError as err:
    if err.code == 401:
        print("PASS: Unauthenticated request rejected with HTTP 401 Unauthorized.")
    else:
        print(f"SECURITY WARNING: Expected HTTP 401, got HTTP {err.code}", file=sys.stderr)
        sys.exit(1)
except Exception as e:
    print(f"Auth probe network failure: {e}", file=sys.stderr)
    sys.exit(1)

# 2. Authenticated Streaming Verification with Authoritative Token Accounting
print(f"\n[2/2] Connecting to {URL} with Bearer authentication (streaming=True)...")
payload = {
    "model": "flint",
    "messages": [
        {"role": "user", "content": "Respond with 'Flint sandbox operational' and nothing else."}
    ],
    "max_tokens": 512,
    "temperature": 0.0,
    "stream": True,
    "stream_options": {"include_usage": True}
}

headers = {"Content-Type": "application/json"}
if API_KEY:
    headers["Authorization"] = f"Bearer {API_KEY}"

data = json.dumps(payload).encode("utf-8")
req = urllib.request.Request(URL, data=data, headers=headers)

start_time = time.time()
first_token_time = None
content_chunks = []
reasoning_chunks = []
chunk_count = 0
server_usage = {}
server_timings = {}

try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        for line in resp:
            line = line.decode("utf-8").strip()
            if not line or not line.startswith("data: "):
                continue
            data_str = line[6:]
            if data_str == "[DONE]":
                break

            chunk = json.loads(data_str)

            # Check for server-authoritative usage and timings in chunk
            if "usage" in chunk and chunk["usage"]:
                server_usage = chunk["usage"]
            if "timings" in chunk and chunk["timings"]:
                server_timings = chunk["timings"]

            choices = chunk.get("choices", [])
            if not choices:
                continue

            delta = choices[0].get("delta", {})
            c = delta.get("content", "")
            r = delta.get("reasoning_content", "")

            if c or r:
                if first_token_time is None:
                    first_token_time = time.time()
                chunk_count += 1

            if c:
                content_chunks.append(c)
            if r:
                reasoning_chunks.append(r)

        duration = time.time() - start_time
        ttft = (first_token_time - start_time) if first_token_time else duration
        full_content = "".join(content_chunks).strip()
        full_reasoning = "".join(reasoning_chunks).strip()

        has_authoritative_usage = "completion_tokens" in server_usage
        completion_tokens = server_usage.get("completion_tokens")
        prompt_tokens = server_usage.get("prompt_tokens")
        server_tok_per_sec = server_timings.get("predicted_per_second")

        gen_duration = duration - ttft if chunk_count > 1 else duration
        client_chunks_per_sec = (chunk_count / gen_duration) if gen_duration > 0 else 0.0

        print(f"Elapsed: {duration:.2f}s | TTFT: {ttft:.2f}s | Chunks: {chunk_count}")
        if has_authoritative_usage:
            print(f"Authoritative Tokens: {completion_tokens} completion (prompt: {prompt_tokens})")
        else:
            print(f"Token Accounting: Chunks only ({chunk_count}); server did not report usage object.")

        if server_tok_per_sec is not None:
            print(f"Decode Velocity: {server_tok_per_sec:.1f} tok/s (server) | {client_chunks_per_sec:.1f} chunks/s (client-observed)")
        else:
            print(f"Decode Velocity: {client_chunks_per_sec:.1f} chunks/s (client-observed; server timings unavailable)")

        if full_reasoning:
            print(f"\n[Reasoning]:\n{full_reasoning}\n")
        print(f"[Content]:\n{full_content}\n")

        # Invariant Assertions
        assert "Flint sandbox operational" in full_content, f"Content assertion failed: '{full_content}'"
        assert len(full_reasoning) > 0, "Reasoning retention assertion failed: empty reasoning_content"
        assert chunk_count > 0, "No response chunks received"
        if has_authoritative_usage:
            assert completion_tokens > 0, "Server reported 0 completion tokens"
        print("Smoke test PASSED (all security and functional assertions verified).")

except Exception as e:
    print(f"Smoke test FAILED: {e}", file=sys.stderr)
    sys.exit(1)
