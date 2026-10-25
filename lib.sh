#!/bin/bash

# $1: source dir
# $2: target dir
copy_s() {
    if [ -f $1 ]; then
        echo "Info: $1 is a file"
        mkdir -p ${2%/*}
        cp -af $1 $2
    elif [ -d $1 ]; then
        echo "Info: $1 is a directory"
        mkdir -p $2
        cp -af $1/* $2/
    else
        echo "Warning: $1 not exist"
    fi
}

# $1: url
# $2: target dir
dl_svn() {
    tmp_dir=$(mktemp -d)

    svn co -q $1 $tmp_dir/tmp

    if [ $? == 0 ]; then
        echo "Info: Svn download success: $1"
        rm -rf $tmp_dir/tmp/.svn

        mkdir -p $2
        cp -af $tmp_dir/tmp/* $2/
    else
        echo "Error: Svn download fail: $1"
    fi

    rm -rf $tmp_dir
}

# $1: git url
# $2: target dir
# $3: branch
dl_git() {
    local repo_url=$1
    local dest_dir=$2
    local branch=${3:-}
    local tmp_dir
    tmp_dir=$(mktemp -d)

    if [ -z "$branch" ]; then
        git clone -q --depth=1 --single-branch "$repo_url" "$tmp_dir/tmp"
    else
        git clone -q --depth=1 --single-branch -b "$branch" "$repo_url" "$tmp_dir/tmp"
    fi

    if [ $? = 0 ]; then
        echo "Info: Git download success: ${repo_url} @ $(git -C "$tmp_dir/tmp" rev-parse --short=12 HEAD)"
        rm -rf "$tmp_dir/tmp/.git"

        mkdir -p "$dest_dir"
        cp -af "$tmp_dir/tmp/." "$dest_dir/"
    else
        echo "Error: Git download fail: ${repo_url}"
        rm -rf "$tmp_dir"
        return 1
    fi

    rm -rf "$tmp_dir"
}

# $1: git url
# $2: target dir
# $3: sub dir
# $4: branch
dl_git_sub() {
    local repo_url=$1
    local dest_dir=$2
    local sub_dir=${3:-}
    local branch=${4:-}
    local cache_key tmp_dir src_dir

    mkdir -p /tmp/opbuild

    cache_key=$(printf '%s' "${repo_url}/tree/${branch}" | md5sum | cut -c 1-12)
    tmp_dir="/tmp/opbuild/${cache_key}"

    if [ ! -d "$tmp_dir/.git" ]; then
        rm -rf "$tmp_dir"
        if [ -z "$branch" ]; then
            git clone -q --depth=1 --single-branch "$repo_url" "$tmp_dir" || return 1
        else
            git clone -q --depth=1 --single-branch -b "$branch" "$repo_url" "$tmp_dir" || return 1
        fi
    else
        git -C "$tmp_dir" remote set-url origin "$repo_url" || return 1
        if [ -z "$branch" ]; then
            git -C "$tmp_dir" fetch -q --depth=1 origin HEAD || return 1
        else
            git -C "$tmp_dir" fetch -q --depth=1 origin "$branch" || return 1
        fi
        git -C "$tmp_dir" reset -q --hard FETCH_HEAD || return 1
        git -C "$tmp_dir" clean -q -fdx || return 1
    fi

    if [ $? = 0 ]; then
        echo "Info: Git-sub download success: ${repo_url}/tree/${branch}/${sub_dir} @ $(git -C "$tmp_dir" rev-parse --short=12 HEAD)"
        src_dir="$tmp_dir"

        if [ -n "$sub_dir" ]; then
            src_dir="$tmp_dir/$sub_dir"
        fi

        if [ -e "$src_dir" ]; then
            mkdir -p "$dest_dir"
            cp -af "$src_dir/." "$dest_dir/"
            rm -rf "$dest_dir/.git"
        else
            echo "Error: Git-sub copy source does not exist: ${src_dir}"
            return 1
        fi
    else
        echo "Error: Git-sub download fail: ${repo_url}/tree/${branch}/${sub_dir}"
        return 1
    fi
}

# $1: url
# $2: target file
dl_curl() {
    tmp_dir=$(mktemp -d)

    curl -skL --retry 3 --connect-timeout 3 -o $tmp_dir/tmp $1

    if [ $? == 0 ]; then
        echo "Info: Curl Download success: $1"
        rm -rf $tmp_dir/.git

        mkdir -p ${2%/*}
        cp -af $tmp_dir/tmp $2
    else
        echo "Error: Download fail: $1"
    fi

    rm -rf $tmp_dir
}
