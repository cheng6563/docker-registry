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
    # coding not support using "/" splic, using "__" replace from "/".
    newname=$(echo "$newname" | sed 's/\//__/g')
    dst="$base_url/$newname"
    echo "pull registry '$src' and push to registry '$dst'"
    docker pull $src
    docker tag $src $dst
    docker push $dst
done