#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/work"
printf '%s\n' 'docker.io/library/alpine:latest' > "$tmp_dir/work/registry.txt"

cat > "$tmp_dir/bin/docker" <<'EOF'
#!/bin/sh
echo "$*" >> "$DOCKER_LOG"
exit 0
EOF

cat > "$tmp_dir/bin/date" <<'EOF'
#!/bin/sh
if [ "$*" = "-u +%s" ]; then
    echo 2000000000
    exit 0
fi

if [ "$1" = "-u" ] && [ "$2" = "-d" ] && [ "$4" = "+%s" ]; then
    case "$3" in
        recent) echo $((2000000000 - 10 * 86400)); exit 0 ;;
        old) echo $((2000000000 - 20 * 86400)); exit 0 ;;
    esac
fi

exit 1
EOF

cat > "$tmp_dir/bin/curl" <<'EOF'
#!/bin/sh
args="$*"

case "$args" in
    *"/v2/library/alpine/manifests/latest"*)
        if [ "${TEST_CASE:-}" = "unreadable" ]; then
            exit 22
        fi
        printf '%s\n' '{"schemaVersion":2,"mediaType":"application/vnd.docker.distribution.manifest.v2+json","config":{"mediaType":"application/vnd.docker.container.image.v1+json","digest":"sha256:config","size":2},"layers":[]}'
        exit 0
        ;;
    *"/v2/library/alpine/blobs/sha256:config"*)
        case "${TEST_CASE:-}" in
            recent) printf '%s\n' '{"created":"recent"}'; exit 0 ;;
            old) printf '%s\n' '{"created":"old"}'; exit 0 ;;
            unreadable) exit 22 ;;
        esac
        ;;
    *"http://registry.test/v2/"*)
        printf '200'
        exit 0
        ;;
esac

echo "unexpected curl args: $args" >&2
exit 22
EOF

chmod +x "$tmp_dir/bin/docker" "$tmp_dir/bin/curl" "$tmp_dir/bin/date"

run_case() {
    case_name="$1"
    expected="$2"
    DOCKER_LOG="$tmp_dir/docker-$case_name.log"
    RUN_LOG="$tmp_dir/run-$case_name.log"
    export DOCKER_LOG TEST_CASE="$case_name"
    : > "$DOCKER_LOG"

    (
        cd "$tmp_dir/work"
        PATH="$tmp_dir/bin:$PATH" DST_REGISTRY_URL="registry.test" sh "$repo_dir/upload_my.sh"
    ) > "$RUN_LOG" 2>&1

    if [ "$expected" = "skip" ]; then
        if grep -q '^pull docker.io/library/alpine:latest$' "$DOCKER_LOG"; then
            echo "expected $case_name to skip pull, but docker pull ran" >&2
            cat "$RUN_LOG" >&2
            exit 1
        fi
        grep -q 'skip registry.test/library/alpine:latest' "$RUN_LOG"
    else
        grep -q '^pull docker.io/library/alpine:latest$' "$DOCKER_LOG"
    fi
}

run_case recent skip
run_case old push
run_case unreadable push
