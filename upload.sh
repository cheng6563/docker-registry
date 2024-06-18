#!/bin/sh
author=$1
if [ -z "$author" ]; then
    echo 'use ./upload.sh ${{ github.actor }}'
    exit 1
fi

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
    dst="ghcr.io/$author/$newname"
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