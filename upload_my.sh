#!/bin/sh
base_url="$MY_REGISTRY_URL"
# echo $MY_REGISTRY_PASSWORD | docker login --username=$MY_REGISTRY_USERNAME --password-stdin $base_url

registry=`cat registry.txt`

if [ -z "$registry" ]; then
    echo "empty registry.txt"
    exit 0
fi

echo "$registry" | while IFS= read -r src
do
    if [ -z "$src" ]; then
        continue
    fi
    newname=$(echo "$src" | sed 's/[^/]*\///')
    dst="$base_url/$newname"
    echo "pull registry '$src' and push to registry '$dst'"

    src_digest=$(docker manifest inspect $src 2>/dev/null | jq -r '.config.digest')
    if [ -z "$src_digest" ]; then
        echo "Failed to get digest for source image $src"
        continue
    fi

    dst_digest=$(docker manifest inspect $dst 2>/dev/null | jq -r '.config.digest')
    
    if [ "$src_digest" = "$dst_digest" ]; then
        echo "exist image with same digest, skip"
        continue
    fi
    docker pull $src
    docker tag $src $dst
    docker push $dst
done