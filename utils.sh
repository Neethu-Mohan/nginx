#!/bin/bash

# Echos out sha function from saved .txt file
get_manifest_sha() {
  local repo=$1
  local arch=$2
  docker pull -q $1 &>/dev/null
  docker manifest inspect $1 > "$2".txt
  sha=""
  i=0
  while [ "$sha" == "" ] && read -r line; do
    architecture=$(jq .manifests[$i].platform.architecture "$2".txt |sed -e 's/^"//' -e 's/"$//')
    if [ "$architecture" = "$2" ];then
      sha=$(jq .manifests[$i].digest "$2".txt  |sed -e 's/^"//' -e 's/"$//')
      echo ${sha}
    fi
    i=$i+1
  done < "$2".txt
}

# Echos out sha function
get_sha() {
  repo=$1
  docker pull $1 &>/dev/null
  sha=$(docker image inspect $1 | jq --raw-output '.[0].RootFS.Layers|.[]')   # [0] means first element of list,[]means all the elments of lists
  echo $sha
}

# Check if base is part of an image
is_base() {
  local base_sha    # alpine
  local image_sha   # new image
  local base_repo=$1
  local image_repo=$2

  base_sha=$(get_sha $base_repo)
  image_sha=$(get_sha $image_repo)

  for i in $base_sha; do
    local found="false"
    for j in $image_sha; do
      if [[ $i = $j ]]; then
        found="true"
        break
      fi
    done
    if [ $found == "false" ]; then
      echo "false"
      return 0
    fi
  done
  echo "true"
}

image_version() {
  local version
  repo=$1    # nginx repo
  version=$(docker run -it $1 /bin/sh -c "nginx -v" |awk '{print$3}')
  echo $version
}

compare() {
  result_arm=$(is_base $1 $2)
  result_arm64=$(is_base $3 $4)
  result_amd64=$(is_base $5 $6)
  if [ $result_arm == "false" ] || [ $result_amd64 == "false" ] || [ $result_arm64 == "false" ];
  then
    echo "true"
  else
    echo "false"
  fi
}

create_manifest() {
  local repo=$1
  local tag1=$2
  local tag2=$3
  local x86=$4
  local rpi=$5
  local arm64=$6
  docker manifest create $repo:$tag1 $x86 $rpi $arm64
  docker manifest create $repo:$tag2 $x86 $rpi $arm64
  docker manifest annotate $repo:$tag1 $x86 --arch amd64
  docker manifest annotate $repo:$tag1 $rpi --arch arm
  docker manifest annotate $repo:$tag1 $arm64 --arch arm64
  docker manifest annotate $repo:$tag2 $x86 --arch amd64
  docker manifest annotate $repo:$tag2 $rpi --arch arm
  docker manifest annotate $repo:$tag2 $arm64 --arch arm64
}

build_image(){
  local repo=$1  # this is the base repo, for example treehouses/alpine
  local arch=$2  #arm arm64 amd64
  local tag_repo=$3  # this is the tag repo, for example treehouses/node
  if [ $# -le 1 ]; then
    echo "missing parameters."
    exit 1
  fi
  sha=$(get_manifest_sha $@)
  echo $sha
  base_image="$repo@$sha"
  echo $base_image
  if [ -n "$sha" ]; then
    tag=$tag_repo-tags:$arch
    sed "s|{{base_image}}|$base_image|g" Dockerfile.template > Dockerfile.$arch
    docker build -t $tag -f Dockerfile.$arch .
  fi
}

deploy_image(){
  local repo="rjole/nginx"
  local arch=$2  #arm arm64 amd64
  tag_arch=$repo-tags:$arch
  tag_time=$(date +%Y%m%d%H%M)
  tag_arch_time=$repo-tags:$arch-$tag_time
  echo $tag_arch_time
  echo 1
  echo $tag_arch
  docker tag $tag_arch $tag_arch_time
  echo 2
  docker push $tag_arch_time
  echo 3
  docker tag $tag_arch_time $tag_arch
  echo 4
  docker push $tag_arch
  echo 5
}
