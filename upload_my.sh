#!/bin/sh

# --- setup base_url ---
if [ -n "$DST_REGISTRY_URL_HTTP" ]; then
    base_url="$DST_REGISTRY_URL_HTTP"
    echo "using HTTP insecure registry: $base_url"
else
    base_url="$DST_REGISTRY_URL"
fi

# docker login (destination registry)
if [ -n "$DST_REGISTRY_USERNAME" ] && [ -n "$DST_REGISTRY_PASSWORD" ]; then
    echo "$DST_REGISTRY_PASSWORD" | docker login --username="$DST_REGISTRY_USERNAME" --password-stdin "$base_url"
fi

# --- SRC_REGISTRY_ACCOUNTS 轮询账号支持 ---
# 格式: user1:pass1,user2:pass2  （逗号分隔多个账号，冒号分隔用户名和密码，密码可含冒号）
_src_account_count=0
_src_accounts=""

if [ -n "$SRC_REGISTRY_ACCOUNTS" ]; then
    # 逗号分隔转换为换行，每项格式为 user:pass
    _src_accounts=$(echo "$SRC_REGISTRY_ACCOUNTS" | tr ',' '\n')
    _src_account_count=$(echo "$_src_accounts" | grep -c .)
    echo "SRC_REGISTRY_ACCOUNTS: 已加载 ${_src_account_count} 个源仓库账号，将轮询使用"
fi

# 轮询登录 docker.io（使用共享文件记录当前轮询索引，兼容 subshell）
_account_idx_file="/tmp/_src_account_idx_$$"
echo "0" > "$_account_idx_file"

src_registry_login() {
    _src_img="$1"
    [ "$_src_account_count" -eq 0 ] && return 0

    # 仅对 docker.io 生效，其他仓库匿名 pull
    [ "${_src_img%%/*}" != "docker.io" ] && return 0

    _cur_idx=$(cat "$_account_idx_file" 2>/dev/null || echo "0")
    # 取第 _cur_idx+1 行
    _pair=$(echo "$_src_accounts" | sed -n "$((_cur_idx + 1))p")
    # 只切第一个冒号，密码可含冒号（对齐 Python split(':', 1)）
    _u="${_pair%%:*}"
    _p="${_pair#*:}"

    echo "  [轮询账号] 使用账号 #$((_cur_idx + 1))/${_src_account_count}: ${_u}"
    echo "$_p" | docker login --username="$_u" --password-stdin "docker.io" 2>&1 | tail -1

    # 更新索引（循环）
    _next=$(( (_cur_idx + 1) % _src_account_count ))
    echo "$_next" > "$_account_idx_file"
}

registry=`cat registry.txt`

if [ -z "$registry" ]; then
    echo "empty registry.txt"
    rm -f "$_account_idx_file"
    exit 0
fi

# destination registry auth args for curl
dst_curl_auth_args() {
    if [ -n "$DST_REGISTRY_USERNAME" ] && [ -n "$DST_REGISTRY_PASSWORD" ]; then
        printf '%s\n' "--user ${DST_REGISTRY_USERNAME}:${DST_REGISTRY_PASSWORD}"
    fi
}

dst_registry_proto() {
    _host="$1"
    _auth=$(dst_curl_auth_args)

    # 200/401 both prove the HTTP registry endpoint is reachable; other cases fall back to HTTPS.
    _code=$(curl -sI $_auth -o /dev/null -w "%{http_code}" "http://${_host}/v2/" 2>/dev/null || true)
    case "$_code" in
        200|401) printf '%s\n' "http" ;;
        *) printf '%s\n' "https" ;;
    esac
}

split_dst_ref() {
    _dst="$1"
    _host="${_dst%%/*}"
    _repo_tag="${_dst#*/}"
    if echo "$_repo_tag" | grep -q ':'; then
        _repo="${_repo_tag%:*}"
        _tag="${_repo_tag##*:}"
    else
        _repo="$_repo_tag"
        _tag="latest"
    fi
}

is_floating_tag() {
    _tag="$1"
    [ "$_tag" = "latest" ] || echo "$_tag" | grep -qiE '^(nightly|dev|master|main)$'
}

manifest_accept='application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json'

# check if tag exists on destination registry
dst_tag_exists() {
    split_dst_ref "$1"
    _auth=$(dst_curl_auth_args)
    _proto=$(dst_registry_proto "$_host")
    _code=$(curl -s -o /dev/null -w "%{http_code}" $_auth \
        -H "Accept: ${manifest_accept}" \
        "${_proto}://${_host}/v2/${_repo}/manifests/${_tag}" 2>/dev/null)
    [ "$_code" = "200" ]
}

json_config_digest() {
    tr -d '\n\r' | sed -n 's/.*"config"[[:space:]]*:[[:space:]]*{[^}]*"digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

json_first_manifest_digest() {
    tr -d '\n\r' |
        sed 's/"digest"/\
"digest"/g' |
        sed -n 's/^"digest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
        sed -n '1p'
}

json_created_value() {
    tr -d '\n\r' | sed -n 's/.*"created"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

created_to_epoch() {
    _created="$1"
    _epoch=$(date -u -d "$_created" +%s 2>/dev/null || true)

    if [ -z "$_epoch" ] && command -v python >/dev/null 2>&1; then
        _epoch=$(python - "$_created" <<'PY' 2>/dev/null || true
import datetime
import re
import sys

s = sys.argv[1]
if s.endswith("Z"):
    s = s[:-1] + "+00:00"

match = re.match(r"^(.*T\d\d:\d\d:\d\d)\.(\d+)(.*)$", s)
if match:
    # Python datetime supports microseconds; Docker/OCI timestamps may use nanoseconds.
    s = match.group(1) + "." + match.group(2)[:6].ljust(6, "0") + match.group(3)

dt = datetime.datetime.fromisoformat(s)
if dt.tzinfo is None:
    dt = dt.replace(tzinfo=datetime.timezone.utc)
print(int(dt.timestamp()))
PY
)
    fi

    case "$_epoch" in
        ''|*[!0-9]*) return 1 ;;
    esac
    printf '%s\n' "$_epoch"
}

dst_image_created_epoch() {
    split_dst_ref "$1"
    _auth=$(dst_curl_auth_args)
    _proto=$(dst_registry_proto "$_host")

    _manifest=$(curl -fsSL $_auth \
        -H "Accept: ${manifest_accept}" \
        "${_proto}://${_host}/v2/${_repo}/manifests/${_tag}" 2>/dev/null) || return 1

    _config_digest=$(printf '%s' "$_manifest" | json_config_digest)
    if [ -z "$_config_digest" ]; then
        _child_digest=$(printf '%s' "$_manifest" | json_first_manifest_digest)
        [ -n "$_child_digest" ] || return 1
        _manifest=$(curl -fsSL $_auth \
            -H "Accept: ${manifest_accept}" \
            "${_proto}://${_host}/v2/${_repo}/manifests/${_child_digest}" 2>/dev/null) || return 1
        _config_digest=$(printf '%s' "$_manifest" | json_config_digest)
    fi

    [ -n "$_config_digest" ] || return 1
    _config=$(curl -fsSL $_auth \
        "${_proto}://${_host}/v2/${_repo}/blobs/${_config_digest}" 2>/dev/null) || return 1
    _created=$(printf '%s' "$_config" | json_created_value)
    [ -n "$_created" ] || return 1
    created_to_epoch "$_created"
}

dst_floating_tag_is_recent() {
    _dst="$1"
    _max_days="$2"

    _created_epoch=$(dst_image_created_epoch "$_dst") || {
        echo "  refresh $_dst — target image created time unavailable"
        return 1
    }
    _now_epoch=$(date -u +%s 2>/dev/null || true)
    case "$_now_epoch" in
        ''|*[!0-9]*)
            echo "  refresh $_dst — current time unavailable"
            return 1
            ;;
    esac

    _age=$((_now_epoch - _created_epoch))
    [ "$_age" -lt 0 ] && _age=0
    _age_days=$((_age / 86400))
    _max_age=$((_max_days * 86400))

    if [ "$_age" -lt "$_max_age" ]; then
        echo "  skip $_dst — floating tag target image is ${_age_days}d old (< ${_max_days}d)"
        return 0
    fi

    echo "  refresh $_dst — floating tag target image is ${_age_days}d old (>= ${_max_days}d)"
    return 1
}

echo "$registry" | while IFS= read -r src
do
    if [ -z "$src" ]; then
        continue
    fi

    # Floating tags are refreshed only when the destination image is stale or unreadable.
    _tag="${src##*:}"
    if is_floating_tag "$_tag"; then
        newname=$(echo "$src" | sed 's/[^/]*\///')
        dst="$base_url/$newname"
        if dst_floating_tag_is_recent "$dst" 15; then
            continue
        fi

        echo "pull registry '$src' and push to registry '$dst'"

        src_registry_login "$src"
        docker pull "$src" || continue
        docker tag "$src" "$dst"
        docker push "$dst" || continue

        # clean up local image
        docker rmi "$src" "$dst" 2>/dev/null
        echo "  cleaned up local images"
        continue
    fi

    # specific version tag: check destination first
    newname=$(echo "$src" | sed 's/[^/]*\///')
    dst="$base_url/$newname"

    if dst_tag_exists "$dst"; then
        echo "  skip $src — tag $dst already exists on destination"
        continue
    fi

    echo "pull registry '$src' and push to registry '$dst'"
    src_registry_login "$src"
    docker pull "$src" || continue
    docker tag "$src" "$dst"
    docker push "$dst" || continue

    # clean up local image
    docker rmi "$src" "$dst" 2>/dev/null
    echo "  cleaned up local images"
done

rm -f "$_account_idx_file"
