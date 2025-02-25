#!/bin/sh
base_url="$MY_REGISTRY_URL"
# echo $MY_REGISTRY_PASSWORD | docker login --username=$MY_REGISTRY_USERNAME --password-stdin $base_url

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
    dst="$base_url/$newname"
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