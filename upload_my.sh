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

# check if tag exists on destination registry
dst_tag_exists() {
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

    _auth=""
    if [ -n "$DST_REGISTRY_USERNAME" ] && [ -n "$DST_REGISTRY_PASSWORD" ]; then
        _auth="--user ${DST_REGISTRY_USERNAME}:${DST_REGISTRY_PASSWORD}"
    fi

    # detect protocol
    _proto="http"
    curl -sI $_auth -o /dev/null -w "%{http_code}" "http://${_host}/v2/" 2>/dev/null | grep -q 200 || _proto="https"

    _code=$(curl -s -o /dev/null -w "%{http_code}" $_auth \
        -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
        "${_proto}://${_host}/v2/${_repo}/manifests/${_tag}" 2>/dev/null)
    [ "$_code" = "200" ]
}

echo "$registry" | while IFS= read -r src
do
    if [ -z "$src" ]; then
        continue
    fi

    # skip :latest or :nightly etc. — pull first then push (dedup handled by docker push)
    _tag="${src##*:}"
    if [ "$_tag" = "latest" ] || echo "$_tag" | grep -qiE '^(nightly|dev|master|main)$'; then
        newname=$(echo "$src" | sed 's/[^/]*\///')
        dst="$base_url/$newname"
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
