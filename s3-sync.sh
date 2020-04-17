#!/bin/bash

set -e

if [[ -z "$1" ]]; then
    echo 'Please provide source directory/s3-url'
    exit 1
fi

if [[ -z "$2" ]]; then
    echo 'Please provide destination directory/s3-url'
    exit 1
fi

aws s3 sync $1 $2
