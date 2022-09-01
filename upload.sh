#!/bin/sh
author=$1
if [ -z "$author" ]; then
    echo 'use ./upload.sh ${{ github.actor }}'
    exit 1
fi

registry=`cat registry.txt`
for line in "$registry"; do
    arr=($line)
    src=`echo "${arr[0]}"`
    dst_name=`echo "${arr[1]}"`
    dst="ghcr.io/$author/$dst_name"
    echo "Pull $src and push to $dst"
    docker pull $src
    docker tag $src $dst
    docker push $dst
done