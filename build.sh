#!/bin/sh

export MIX_ENV=prod

mix deps.get --only=prod
mix release

cp _build/${MIX_ENV}/rel/bakeware/electric .
