#!/bin/sh

# --- setup base_url ---
if [ -n "$DST_REGISTRY_URL_HTTP" ]; then
    base_url="$DST_REGISTRY_URL_HTTP"
    echo "using HTTP insecure registry: $base_url"
else
    base_url="$DST_REGISTRY_URL"
fi

# docker login
if [ -n "$DST_REGISTRY_USERNAME" ] && [ -n "$DST_REGISTRY_PASSWORD" ]; then
    echo "$DST_REGISTRY_PASSWORD" | docker login --username="$DST_REGISTRY_USERNAME" --password-stdin "$base_url"
fi

registry=`cat registry.txt`

if [ -z "$registry" ]; then
    echo "empty registry.txt"
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
    docker pull "$src" || continue
    docker tag "$src" "$dst"
    docker push "$dst" || continue

    # clean up local image
    docker rmi "$src" "$dst" 2>/dev/null
    echo "  cleaned up local images"
done
