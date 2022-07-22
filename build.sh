#!/bin/sh

export MIX_ENV=dev

mix deps.get
mix release

cp _build/dev/rel/bakeware/electric .
