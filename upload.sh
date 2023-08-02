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
    docker pull $src
    docker tag $src $dst
    docker push $dst
done