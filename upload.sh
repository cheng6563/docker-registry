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

for line in "$registry"; do
    arr=($line)
    src=`echo "${arr[0]}"`
    dst_name=`echo "${arr[1]}"`
    dst="ghcr.io/$author/$dst_name"
    echo "push registry $src and push to registry $dst"
    docker pull $src
    docker tag $src $dst
    docker push $dst
done