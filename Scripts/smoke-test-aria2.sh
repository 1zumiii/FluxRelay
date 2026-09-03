#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="${ARIA2_BINARY:-$ROOT_DIR/.build/app/FluxRelay.app/Contents/Resources/engine/aria2c}"
TEST_ROOT="${TMPDIR:-/tmp}/motrix-native-aria2-smoke.$$"
SOURCE_DIR="$TEST_ROOT/source"
DOWNLOAD_DIR="$TEST_ROOT/download"
BASE_PORT=$((40000 + ($$ % 10000)))
HTTP_PORT="${HTTP_PORT:-$BASE_PORT}"
RPC_PORT="${RPC_PORT:-$((BASE_PORT + 1))}"
RPC_SECRET="motrix-native-smoke-test"
HTTP_PID=""
ENGINE_PID=""

cleanup() {
  if [ -n "$ENGINE_PID" ]; then
    kill "$ENGINE_PID" >/dev/null 2>&1 || true
    wait "$ENGINE_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$HTTP_PID" ]; then
    kill "$HTTP_PID" >/dev/null 2>&1 || true
    wait "$HTTP_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

if [ ! -x "$ENGINE" ]; then
  echo "Missing aria2 engine: $ENGINE" >&2
  exit 1
fi

mkdir -p "$SOURCE_DIR" "$DOWNLOAD_DIR"
dd if=/dev/zero of="$SOURCE_DIR/smoke-source.bin" bs=1048576 count=4 2>/dev/null
EXPECTED_SHA="$(shasum -a 256 "$SOURCE_DIR/smoke-source.bin" | awk '{print $1}')"

python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$SOURCE_DIR" \
  >"$TEST_ROOT/http.log" 2>&1 &
HTTP_PID=$!

attempt=0
while [ "$attempt" -lt 50 ]; do
  if curl --silent --fail --head \
    "http://127.0.0.1:$HTTP_PORT/smoke-source.bin" >/dev/null 2>&1; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done
if [ "$attempt" -eq 50 ]; then
  echo "Local HTTP server did not become ready." >&2
  exit 1
fi

"$ENGINE" \
  --enable-rpc=true \
  --rpc-listen-all=false \
  --rpc-listen-port="$RPC_PORT" \
  --rpc-secret="$RPC_SECRET" \
  --dir="$DOWNLOAD_DIR" \
  --max-connection-per-server=64 \
  --split=64 \
  --disable-ipv6=true \
  --file-allocation=none \
  --console-log-level=warn \
  --summary-interval=0 \
  >"$TEST_ROOT/aria2.log" 2>&1 &
ENGINE_PID=$!

rpc() {
  curl --silent --show-error --fail \
    --header 'Content-Type: application/json' \
    --data "$1" \
    "http://127.0.0.1:$RPC_PORT/jsonrpc"
}

attempt=0
version_response=""
while [ "$attempt" -lt 50 ]; do
  version_response="$(rpc '{"jsonrpc":"2.0","id":"version","method":"aria2.getVersion","params":["token:'"$RPC_SECRET"'"]}' 2>/dev/null || true)"
  if printf '%s' "$version_response" | grep -F '"version":"1.37.0-git.9e72735"' >/dev/null; then
    break
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

if ! printf '%s' "$version_response" | grep -F '"version":"1.37.0-git.9e72735"' >/dev/null; then
  echo "aria2 RPC did not become ready." >&2
  exit 1
fi

add_response="$(rpc '{"jsonrpc":"2.0","id":"add","method":"aria2.addUri","params":["token:'"$RPC_SECRET"'",["http://127.0.0.1:'"$HTTP_PORT"'/smoke-source.bin"]]}')"
gid="$(printf '%s' "$add_response" | sed -n 's/.*"result":"\([^"]*\)".*/\1/p')"
if [ -z "$gid" ]; then
  echo "aria2 RPC did not return a download GID: $add_response" >&2
  exit 1
fi

attempt=0
status_response=""
while [ "$attempt" -lt 100 ]; do
  status_response="$(rpc '{"jsonrpc":"2.0","id":"status","method":"aria2.tellStatus","params":["token:'"$RPC_SECRET"'","'"$gid"'",["status","errorCode","errorMessage"]]}')"
  if printf '%s' "$status_response" | grep -F '"status":"complete"' >/dev/null; then
    break
  fi
  if printf '%s' "$status_response" | grep -F '"status":"error"' >/dev/null; then
    echo "aria2 download failed: $status_response" >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  sleep 0.1
done

ACTUAL_SHA="$(shasum -a 256 "$DOWNLOAD_DIR/smoke-source.bin" | awk '{print $1}')"
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "Downloaded file checksum mismatch." >&2
  exit 1
fi

rpc '{"jsonrpc":"2.0","id":"shutdown","method":"aria2.shutdown","params":["token:'"$RPC_SECRET"'"]}' >/dev/null
wait "$ENGINE_PID"
ENGINE_PID=""

echo "aria2 RPC and HTTP download smoke test passed (SHA-256 $ACTUAL_SHA)."
