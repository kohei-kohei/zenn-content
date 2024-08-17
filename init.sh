#!/bin/zsh

set -e

WORKDIR=/home/zenn-content

echo '# docker run --rm -v $PWD/articles:$WORKDIR/articles -v $PWD/images:$WORKDIR/images -p 8000:8000 -it zenn-cli /bin/bash'
docker run --rm -v $PWD/articles:$WORKDIR/articles -v $PWD/images:$WORKDIR/images -p 8000:8000 -it zenn-cli /bin/bash
