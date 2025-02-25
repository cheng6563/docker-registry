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

is_subset() {
    local SUB="$1"
    local ALL="$2"
    
    local old_ifs="$IFS"
    IFS=$'\n'
    
    for line in $SUB; do
        [ -z "$line" ] && continue
        
        if ! echo "$ALL" | grep -Fq "$line"; then
            IFS="$old_ifs"
            return 1
        fi
    done
    
    IFS="$old_ifs"
    return 0
}

echo "$registry" | while IFS= read -r src
do
    if [ -z "$src" ]; then
        continue
    fi
    newname=$(echo "$src" | sed 's/[^/]*\///')
    dst="ghcr.io/$author/$newname"
    echo "pull registry '$src' and push to registry '$dst'"

    dst_degests=`docker manifest inspect $dst -v | grep 'digest' | sed 's/[^a-zA-Z0-9_]//g'`
    src_degests=`docker manifest inspect $src -v | grep 'digest' | sed 's/[^a-zA-Z0-9_]//g'`

    if [ -n "$dst_degests" ] && is_subset "$dst_degests" "$src_degests"; then
        echo "skip $src"
        continue
    fi

    docker pull $src
    docker tag $src $dst
    docker push $dst
done