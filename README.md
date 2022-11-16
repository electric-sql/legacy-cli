<a href="https://electric-sql.com">
  <picture>
    <source media="(prefers-color-scheme: dark)"
        srcset="https://raw.githubusercontent.com/electric-sql/meta/main/identity/ElectricSQL-logo-light-trans.svg"
    />
    <source media="(prefers-color-scheme: light)"
        srcset="https://raw.githubusercontent.com/electric-sql/meta/main/identity/ElectricSQL-logo-black.svg"
    />
    <img alt="ElectricSQL logo"
        src="https://raw.githubusercontent.com/electric-sql/meta/main/identity/ElectricSQL-logo-black.svg"
    />
  </picture>
</a>

# ElectricSQL CLI

The ElectricSQL CLI is the command line interface utility for the [ElectricSQL](https://electric-sql.com) service. It's developed in Elixir using [Optimus](https://github.com/funbox/optimus) and [Bakeware](https://github.com/bake-bake-bake/bakeware) and is published under the [Apache 2.0 License](https://github.com/electric-sql/electric-sql-cli/blob/master/LICENSE) at [github.com/electric-sql/cli](https://github.com/electric-sql/cli).

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

## Usage

```sh
./dist/electric --help
```


## Migrations

The `migrations` command lets you create 

migrations init:

Creates a folder for migrations and a new migration called init


migrations add --dir xxx named

Adds a new migration to the folder

The migration is a file called migration.sql it has an informative header 

Adds the migration name and tile to the manifest file



migrations build --dir xxx


builds satellite versions of the sql files

generates/updates a manifest file holding at the root with the following:

- name
- title
- sha256 a sha of a normalised version of the migration.sql
- satellite_body

Before building the sha26 is checked against the current sha256 it only performs the build if it has changed and also updates the sha256

This will also generate an index.js in the root of the migrations in build/local



migrations sync --app xxx --env xxx


First updates the satellite versions locally


Checks the local against existing versions on the server. If the server has a migration with the same name but different sha256 then it fails with a useful message.

Otherwise it will copy any missing migrations to the server in order.

If a server name is lower han an existing one on the server then it will fail.


Finally this will generate a index.js file in the root of the migrations in build/<env>. It will download all the satellite_body from the server rather than using local versions as it is possible for them to differ with tooling changes.

migrations list

Will show a list of all the migrations and their status in every env in the app


migration revert <migration_name> --app xxx --env xxx

will copy the remote version to replace the local one
