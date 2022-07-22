#!/bin/sh

export MIX_ENV=prod

rm -rf _build

mix deps.get
mix release

mkdir -p -- "dist"
cp _build/prod/rel/bakeware/electric ./dist
