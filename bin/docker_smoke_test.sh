#!/bin/bash
# Smoke-test the production Docker image end to end:
#
#   1. build the image from ./Dockerfile
#   2. assert the Elixir/OTP versions inside it are the ones Dockerfile asks for
#   3. start a throwaway Postgres (with SSL — the prod config requires it)
#   4. load priv/repo/structure.sql, then run /app/bin/migrate
#   5. boot /app/bin/server and wait for GET /healthcheck to return 200
#   6. query Postgres from inside the running release
#
# Useful after an Elixir/OTP/deps bump: a green run means the release compiles,
# the config providers evaluate, the supervision tree comes up and the app
# serves HTTP.
#
# Everything runs on the local Docker daemon in containers this script creates
# and destroys. The script refuses to start if the env file names a database
# host that is not local — never point it at stage or production.
set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

IMAGE="sanbase:smoke"
ENV_FILE=".env.docker.test"
CONTAINER_TYPE="web"
PORT="4000"
BOOT_TIMEOUT="120"
SKIP_BUILD=false
KEEP=false
FROM_SCRATCH=false

NETWORK="sanbase-smoke-net"
NETWORK_ID=""
PG_CONTAINER="sanbase-smoke-postgres"
APP_CONTAINER="sanbase-smoke-app"
PG_IMAGE="sanbase-smoke-postgres:local"
PG_DB="sanbase_smoke"

# Fixed container names mean two concurrent runs fight over them, so only one
# run at a time. mkdir is atomic, which `[ -e ]` plus touch is not.
LOCK_DIR="${TMPDIR:-/tmp}/sanbase-docker-smoke-test.lock"
HOLDS_LOCK=false

usage() {
  cat <<EOF
Usage: $0 [options]

  --skip-build           Reuse an existing '$IMAGE' image instead of building
  --tag NAME             Image tag to build/use (default: $IMAGE)
  --env-file FILE        Env file passed to docker run (default: $ENV_FILE)
  --container-type TYPE  CONTAINER_TYPE for the release: web|all|scrapers|... (default: $CONTAINER_TYPE)
  --port PORT            Host port to publish the endpoint on (default: $PORT)
  --timeout SECONDS      How long to wait for /healthcheck (default: $BOOT_TIMEOUT)
  --from-scratch         Run all migrations on an empty DB instead of loading structure.sql
  --keep                 Leave the containers running after a successful run
  -h, --help             Show this help

Examples:
  $0                              # full run: build, boot, verify
  $0 --skip-build --keep          # reboot an already built image and poke at it
  $0 --container-type all         # exercise every supervision tree
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true; shift ;;
    --tag) IMAGE="$2"; shift 2 ;;
    --env-file) ENV_FILE="$2"; shift 2 ;;
    --container-type) CONTAINER_TYPE="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --timeout) BOOT_TIMEOUT="$2"; shift 2 ;;
    --from-scratch) FROM_SCRATCH=true; shift ;;
    --keep) KEEP=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$1"; }
ok()   { printf '\033[1;32m    ok: %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mFAILED: %s\033[0m\n' "$1" >&2; }

# --- Safety: the release must only ever talk to a local database -------------
#
# .env.dev is deliberately not usable here: it carries stage ClickHouse URLs and
# live third party API keys. Booting a release against a deployed database — even
# read-only — is not something this script will do.
assert_local_only() {
  local file="$1" offenders="" url host

  if [ ! -f "$file" ]; then
    fail "env file '$file' not found"
    exit 1
  fi

  # Only uncommented assignments matter; commented-out URLs are inert.
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    # Strip scheme, then userinfo, then everything from the port/path on.
    host=$(printf '%s' "$url" | sed -E 's#^[a-zA-Z+]+://##; s#^[^@/]*@##; s#[:/?].*$##')
    case "$host" in
      localhost|127.0.0.1|::1|"$PG_CONTAINER") ;;
      "") ;;
      *) offenders="$offenders $host" ;;
    esac
  done < <(grep -E '^[[:space:]]*(DATABASE_URL|CLICKHOUSE_DATABASE_URL|CLICKHOUSE_READONLY_DATABASE_URL)=' "$file" |
             sed -E 's/^[^=]+=//' | tr -d "\"'")

  if [ -n "$offenders" ]; then
    fail "'$file' points at non-local database host(s):$offenders"
    echo "This script only boots the release against the throwaway local Postgres" >&2
    echo "it starts itself. Use .env.docker.test, or a copy of it." >&2
    exit 1
  fi

  # Second layer: any deployed hostname anywhere in the file, whatever the var.
  if grep -nE '(stage\.san|production\.san|rds\.amazonaws\.com)' "$file" | grep -vqE '^[0-9]+:[[:space:]]*#'; then
    fail "'$file' references a stage/production host"
    grep -nE '(stage\.san|production\.san|rds\.amazonaws\.com)' "$file" | grep -vE '^[0-9]+:[[:space:]]*#' >&2
    exit 1
  fi

  ok "env file '$file' is local-only"
}

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    fail "another smoke test run is already in progress"
    echo "Lock: $LOCK_DIR" >&2
    echo "If no run is active, the previous one died hard — remove it with: rmdir $LOCK_DIR" >&2
    exit 1
  fi
  HOLDS_LOCK=true
}

# `docker rm -f` returns before the daemon releases the name, so a following
# `docker run --name` can still lose to it with a Conflict error.
remove_container() {
  local name="$1"
  docker rm -f "$name" >/dev/null 2>&1 || true
  for _ in $(seq 1 30); do
    docker ps -a --format '{{.Names}}' | grep -qx "$name" || return 0
    sleep 1
  done
  fail "container '$name' still exists after 'docker rm -f'"
  exit 1
}

# Unlike containers, `docker network create` will happily make a second network
# with an existing name, and then `--network <name>` is ambiguous. Always work
# with a resolved ID, and clear out duplicates left by an interrupted run.
ensure_network() {
  local ids id count
  ids=$(docker network ls --filter "name=^${NETWORK}$" -q)
  count=$(printf '%s' "$ids" | grep -c . || true)

  if [ "$count" -gt 1 ]; then
    for id in $ids; do docker network rm "$id" >/dev/null 2>&1 || true; done
    ids=""
  fi

  if [ -z "$ids" ]; then
    NETWORK_ID=$(docker network create "$NETWORK")
  else
    NETWORK_ID="$ids"
  fi
}

cleanup() {
  local status=$?
  if [ "$status" -ne 0 ] && docker ps -a --format '{{.Names}}' | grep -qx "$APP_CONTAINER"; then
    printf '\n\033[1;33m--- last 80 log lines from %s ---\033[0m\n' "$APP_CONTAINER" >&2
    docker logs --tail 80 "$APP_CONTAINER" 2>&1 | sed 's/^/    /' >&2
  fi

  if [ "$KEEP" = true ] && [ "$status" -eq 0 ]; then
    [ "$HOLDS_LOCK" = true ] && rmdir "$LOCK_DIR" 2>/dev/null || true
    cat <<EOF

Containers left running (--keep):
  app:      $APP_CONTAINER   http://localhost:$PORT/healthcheck
  postgres: $PG_CONTAINER
  logs:     docker logs -f $APP_CONTAINER
  shell:    docker exec -it $APP_CONTAINER /app/bin/sanbase remote
  teardown: docker rm -f $APP_CONTAINER $PG_CONTAINER && docker network rm $NETWORK
EOF
    return
  fi

  docker rm -f "$APP_CONTAINER" "$PG_CONTAINER" >/dev/null 2>&1 || true
  for id in $(docker network ls --filter "name=^${NETWORK}$" -q); do
    docker network rm "$id" >/dev/null 2>&1 || true
  done

  [ "$HOLDS_LOCK" = true ] && rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

# Expected versions come from the Dockerfile itself, so this never drifts.
expected_elixir=$(sed -nE 's/^ARG ELIXIR_VERSION=([0-9.]+).*/\1/p' Dockerfile | head -1)
expected_otp_major=$(sed -nE 's/^ARG OTP_VERSION=([0-9]+).*/\1/p' Dockerfile | head -1)

step "Checking prerequisites"
docker version >/dev/null
acquire_lock
assert_local_only "$ENV_FILE"
if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  fail "port $PORT is already in use — pass --port to pick another one"
  exit 1
fi
ok "docker is up, port $PORT is free"

step "Building $IMAGE from ./Dockerfile"
if [ "$SKIP_BUILD" = true ]; then
  docker image inspect "$IMAGE" >/dev/null 2>&1 || { fail "--skip-build given but '$IMAGE' does not exist"; exit 1; }
  ok "reusing existing $IMAGE"
else
  # This is the same build CI runs; the Rust NIF and asset stages are the ones
  # most likely to break on an Elixir/OTP bump.
  docker build -t "$IMAGE" --build-arg GIT_COMMIT="$(git rev-parse HEAD)" .
  ok "built $IMAGE"
fi

step "Verifying Elixir/OTP inside the image"
# `eval` runs config/runtime.exs, so the env file is required even though
# nothing connects to a database here.
versions=$(docker run --rm --env-file "$ENV_FILE" "$IMAGE" \
  /app/bin/sanbase eval \
  'IO.puts("elixir=" <> System.version() <> " otp=" <> List.to_string(:erlang.system_info(:otp_release)))' |
  grep -o 'elixir=[^ ]* otp=[0-9]*' | tail -1)
actual_elixir=$(printf '%s' "$versions" | sed -E 's/elixir=([^ ]*).*/\1/')
actual_otp=$(printf '%s' "$versions" | sed -E 's/.*otp=([0-9]*)/\1/')

if [ "$actual_elixir" != "$expected_elixir" ] || [ "$actual_otp" != "$expected_otp_major" ]; then
  fail "version mismatch: image has Elixir $actual_elixir / OTP $actual_otp, Dockerfile asks for Elixir $expected_elixir / OTP $expected_otp_major"
  exit 1
fi
ok "Elixir $actual_elixir, OTP $actual_otp — and config/runtime.exs evaluated cleanly"

step "Starting throwaway Postgres"
ensure_network
if ! docker image inspect "$PG_IMAGE" >/dev/null 2>&1; then
  # config/runtime.exs sets `Sanbase.Repo, ssl: [verify: :verify_none]` in :prod,
  # and postgrex treats a keyword list as "SSL required", so a stock postgres
  # image would refuse the connection. Self-signed is enough for verify_none.
  # pgvector's image rather than plain postgres: priv/repo/structure.sql does
  # `CREATE EXTENSION vector` (and citext, which ships with postgres).
  docker build -t "$PG_IMAGE" - <<'DOCKERFILE'
FROM pgvector/pgvector:pg17
RUN mkdir -p /certs \
 && openssl req -new -x509 -days 3650 -nodes -text -subj "/CN=sanbase-smoke-postgres" \
      -out /certs/server.crt -keyout /certs/server.key \
 && chmod 600 /certs/server.key \
 && chown postgres:postgres /certs/server.key /certs/server.crt
CMD ["postgres", "-c", "ssl=on", "-c", "ssl_cert_file=/certs/server.crt", "-c", "ssl_key_file=/certs/server.key"]
DOCKERFILE
fi

remove_container "$PG_CONTAINER"
docker run -d --name "$PG_CONTAINER" --network "$NETWORK_ID" \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB="$PG_DB" \
  "$PG_IMAGE" >/dev/null

for _ in $(seq 1 60); do
  if docker exec "$PG_CONTAINER" pg_isready -U postgres -d "$PG_DB" >/dev/null 2>&1; then break; fi
  sleep 1
done
docker exec "$PG_CONTAINER" pg_isready -U postgres -d "$PG_DB" >/dev/null 2>&1 || {
  fail "Postgres never became ready"; exit 1
}
ok "$PG_CONTAINER ready with ssl=on"

step "Preparing the schema"
if [ "$FROM_SCRATCH" = true ]; then
  ok "skipping structure.sql (--from-scratch): every migration will run"
else
  # structure.sql is a pg_dump that also inserts the schema_migrations rows, so
  # the following migrate run is a no-op unless there are unreleased migrations.
  docker exec -i "$PG_CONTAINER" psql -q -v ON_ERROR_STOP=1 -U postgres -d "$PG_DB" \
    < "$REPO_ROOT/priv/repo/structure.sql" >/dev/null
  ok "loaded priv/repo/structure.sql"
fi

docker run --rm --network "$NETWORK_ID" --env-file "$ENV_FILE" \
  -e CONTAINER_TYPE=migrations \
  "$IMAGE" /app/bin/migrate
ok "/app/bin/migrate succeeded"

step "Booting the release (CONTAINER_TYPE=$CONTAINER_TYPE)"
remove_container "$APP_CONTAINER"

# rel/env.sh.eex builds RELEASE_NODE as
# sanbase-${CONTAINER_TYPE}@${POD_IP dots as dashes}.${NAMESPACE}.pod.cluster.local.
# That name resolves via k8s DNS in a cluster and nowhere else, and
# `bin/sanbase rpc` has to resolve it to attach, so point it at loopback.
env_value() {
  grep -E "^[[:space:]]*$1=" "$ENV_FILE" | tail -1 | sed -E 's/^[^=]+=//' | tr -d "\"'"
}
pod_ip=$(env_value POD_IP)
namespace=$(env_value NAMESPACE)
add_host=()
if [ -n "$pod_ip" ] && [ -n "$namespace" ]; then
  release_host="$(printf '%s' "$pod_ip" | tr '.' '-').${namespace}.pod.cluster.local"
  add_host=(--add-host "${release_host}:127.0.0.1")
fi

docker run -d --name "$APP_CONTAINER" --network "$NETWORK_ID" --env-file "$ENV_FILE" \
  ${add_host[@]+"${add_host[@]}"} \
  -e CONTAINER_TYPE="$CONTAINER_TYPE" \
  -e PORT=4000 \
  -p "$PORT":4000 \
  "$IMAGE" /app/bin/server >/dev/null

healthy=false
for _ in $(seq 1 "$BOOT_TIMEOUT"); do
  if ! docker ps --format '{{.Names}}' | grep -qx "$APP_CONTAINER"; then
    fail "container exited during boot"
    exit 1
  fi
  if curl -fsS -o /dev/null --max-time 5 "http://localhost:$PORT/healthcheck" 2>/dev/null; then
    healthy=true
    break
  fi
  sleep 1
done

if [ "$healthy" != true ]; then
  fail "GET /healthcheck did not return 200 within ${BOOT_TIMEOUT}s"
  exit 1
fi
ok "GET /healthcheck returned 200 — endpoint is serving"

step "Querying Postgres from inside the running release"
# `rpc` also proves distribution and the release cookie work. It is unavailable
# when RELEASE_DISTRIBUTION=none, in which case fall back to reading the log.
if docker exec "$APP_CONTAINER" /app/bin/sanbase rpc \
     'IO.puts("rows=" <> inspect(Sanbase.Repo.query!("select 1").rows))' 2>/dev/null |
     grep -q 'rows=\[\[1\]\]'; then
  ok "Sanbase.Repo answered 'select 1' over SSL"
elif grep -q 'RELEASE_DISTRIBUTION=none' "$ENV_FILE" &&
     ! grep -qE '^[[:space:]]*#[[:space:]]*RELEASE_DISTRIBUTION=none' "$ENV_FILE"; then
  printf '\033[1;33m    skipped: RELEASE_DISTRIBUTION=none, rpc unavailable\033[0m\n'
else
  fail "could not query Postgres through the release"
  exit 1
fi

step "Checking the boot log for errors"
if docker logs "$APP_CONTAINER" 2>&1 | grep -nE '\[error\]|\[emergency\]|GenServer .* terminating|Postgrex.Protocol .* failed to connect'; then
  fail "errors present in the boot log (see above)"
  exit 1
fi
ok "no errors logged during boot"

printf '\n\033[1;32mSmoke test passed: %s boots and serves on Elixir %s / OTP %s.\033[0m\n' \
  "$IMAGE" "$actual_elixir" "$actual_otp"
