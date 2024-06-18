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

    # 插入新逻辑，判断是否需要直接转发
    tag=$(echo "$src" | awk -F: '{print $2}')
    if [ -z "$tag" ]; then
        tag="latest"
    fi

    if echo "$tag" | grep -Eq '^(latest|[^.]+(\.[^.]+)?)$'; then
        docker pull $src
        docker tag $src $dst
        docker push $dst
        continue
    fi

    docker manifest inspect $dst > /dev/null 2>&1
    
    if [ "$?" -eq 0 ]; then
        echo "exist image, skip"
        continue
    fi
    docker pull $src
    docker tag $src $dst
    docker push $dst
done