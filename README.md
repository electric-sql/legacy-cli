![Status](https://img.shields.io/badge/status-alpha-red.svg)
[![License](https://img.shields.io/badge/license-Apache-green.svg)](LICENSE.md)
[![CircleCI](https://circleci.com/gh/electric-sql/electric-sql-cli/tree/main.svg?style=shield&circle-token=67d43361b7c2aa039a0eef39d3617a9f481e54c5)](https://circleci.com/gh/electric-sql/electric-sql-cli/tree/main)

# Electric SQL CLI

The Electric SQL CLI is the command line interface utility for the [Electric SQL](https://electricdb-sql.com) service. It's developed in Elixir using [Optimus](https://github.com/funbox/optimus) and [Bakeware](https://github.com/bake-bake-bake/bakeware) and is published under the [Apache 2.0 License](https://github.com/electric-sql/electric-sql-cli/blob/master/LICENSE) at [github.com/electric-sql/electric-sql-cli](https://github.com/electric-sql/electric-sql-cli).

## Dependencies

You need [Elixir](https://elixir-lang.org/install.html) then run:

```sh
mix deps.get
```

## Test

Run tests using:

```sh
mix test
```

## Develop

You can run the command locally using:

```sh
mix dev
```

Arguments are passed directly to the CLI, e.g.:

```sh
# equivalent to `electric auth whoami`
mix dev auth whoami
```

Alternatively, you can build the executable:

```sh
./build.sh
```

And run it:

```sh
./electric
```

## Release

```sh
./release.sh
```

This creates a binary at `./dist/electric` and needs to be run on the OS you are targetting.
See also https://github.com/bake-bake-bake/bakeware#static-compiling-openssl-into-erlang-distribution
