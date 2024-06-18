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

    src_manifest=$(docker manifest inspect $src 2>/dev/null)
    if [ -z "$src_manifest" ]; then
        echo "Failed to get manifest for source image $src"
        continue
    fi

    dst_manifest=$(docker manifest inspect $dst 2>/dev/null)
    
    if [ -z "$dst_manifest" ]; then
        echo "Destination image $dst does not exist, proceeding to transfer."
    else
        src_config_digest=$(echo $src_manifest | jq -r '.config.digest')
        dst_config_digest=$(echo $dst_manifest | jq -r '.config.digest')

        src_layers_digest=$(echo $src_manifest | jq -r '.layers[].digest' | sort)
        dst_layers_digest=$(echo $dst_manifest | jq -r '.layers[].digest' | sort)

        if [ "$src_config_digest" = "$dst_config_digest" ] && [ "$src_layers_digest" = "$dst_layers_digest" ]; then
            echo "exist image with same digest, skip"
            continue
        fi
    fi

    docker pull $src
    docker tag $src $dst
    docker push $dst
done