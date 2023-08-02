#!/bin/bash
base_url="cheng6563-docker.pkg.coding.net/container-registry/public"
echo $CODING_PASSWORD | docker login --username=$CODING_USERNAME --password-stdin $base_url

registry=`cat registry.txt`

if [ -z "$registry" ]; then
    echo "empty registry.txt"
    exit 0
fi

for line in "$registry"; do
    arr=(`echo ${line}`);
    src=`echo "${arr[0]}"`
    dst_name=`echo "${arr[1]}"`

    if [ -z "$src" ]; then
        continue
    fi
    if [ -z "$dst_name" ]; then
        dst_name=${src//\//__}
    fi


    dst="$base_url/$dst_name"
    echo "pull registry $src and push to registry $dst"
    docker pull $src
    docker tag $src $dst
    docker push $dst
done