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

The following examples assume that you have the `./dist/electric` binary on your path.

## Usage

```sh
electric --help
```

The optional `--verbose` flag can be added to any command to output some useful
information about what the client is doing.

Prefixing a command or sub command with `help` will print detailed usage information. For example:

```sh
electric help auth whoami
```

## Authentication

Login using:

```sh
electric auth login EMAIL [--password PASSWORD]
```

Where your `EMAIL` is the email address associated with your ElectricSQL account. You will be prompted to enter your password if not provided.

## Configuration

### Init

```sh
electric init APP [--env ENV] [--migrations-dir MIGRATIONS_DIR] [--output-dir OUTPUT_DIR]
```

Creates a new folder for migrations in your current directory called 'migrations' and adds a new migration  folder to it with a name automatically derived from the current time in UTC and the title `init` e.g. `20221116162204816_init`. Inside this folder will be a file called `migration.sql`. You should write your initial SQLite DDL SQL into this file.

The `APP` and optinally `ENV` you give should be copied from the sync service connection details provided by the ElectricSQL console. You specify here once, and the CLI stores in an `electric.json` file so you don't have to keep re-typing it.

Note that you can also sync down migrations from an existing app using:

```sh
electric init APP --sync-down
```

### Update

You can update your config using `electric config update`. See the options with:

```sh
electric config update --help
```

## Migrations command

The `migrations` command lets you create new migrations, build electrified javascript distributions of the migrations to use in your project, and sync your migrations to our cloud service.

### new

```sh
electric migrations new NAME
```

This adds a new migration to the `migrations` folder with a name automatically derived from the current time in UTC and the given `NAME`, which should be a short human readable description of the new migration.

### build

```sh
electric migrations build [--env ENV] [--postgres] [--satellite]
```

Builds a bundled javascript file at `.electric/:app/:env/index.js` that can be imported into your local application using the `@config` or `@app/:env` symlinks, e.g.:

```ts
import config from '.electric/@config'
```

See the [configuration guide](https://electric-sql.com/docs/usage/configure) for more details.

The optional flag `--postgres` will also build a `postgres.sql` file in each migrations' folder with the PostgreSQL formatted migrations. This is useful for applying migrations manually to Postgres.

The optional flag `--satellite` will also build a `satellite.sql` file in each migrations' folder that's designed to be applied to SQLite. This is primarily useful for testing and advanced debugging.

### sync

```sh
electric sync [--env ENV]
```

Synchronises changes you have made to migration SQL files in your local `migrations` folder up to the backend servers, and builds a new javascript file at `.electric/:app/:env/index.js` that matches the newly synchronised set of migrations. The metadata in this file will have a `"build": "server"` to indicate that it was built directly from the named backend environment.

By default this will sync to the `default` environment for your app. If you want to use a different one give its name with `--env ENV`.

If the app environment on our servers already has a migration with the same name but different sha256 then this synchronisation will fail because a migration cannot be modified once it has been applied.

If this happens you have two options, either:

1. revert the local changes you've made to the conflicted migration using `electric migrations revert NAME`; or
2. reset and re-provision the whole environment using `electric reset` (warning: causes data loss)

See below for information on both commands. Note also that if a migration has a name that is lower in sort order than one already applied on the server this will also error.

### list

```sh
electric migrations list [--env ENV]
```

Will show a list of all the migrations and their status in every env in the app.

### revert

```sh
electric migrations revert NAME [--env ENV]
```

This will copy the named migration from the ElectricSQL server to replace the local one. By default this will use the `default` environment, if you want to use a different one you can specify it with `--env ENV`.

If you're having problems with your local migrations, you can force revert:

```sh
electric migrations revert NAME --force
```

And you can revert all of the local migrations to match the migrations that have been applied on the server. This is like a force reset of the local migrations folder:

```sh
electric migrations revert --all
```

Remeber to `electric build` after resetting before importing into your local app.

### reset

> WARNING: Use `reset` with extreme care (and usually only in development) as it explicitly causes data loss.

If you get stuck and need to reset the migrations that have been applied on the server, you can wipe and re-provision your environment using:

```sh
electric reset [--env ENV]
```

This is like a force reset of the server migrations. Remember to `electric sync` to upload your local migrations to the new server environment before restarting replication.

## Contributing

See the [Community Guidelines](https://github.com/electric-sql/meta) including the [Guide to Contributing](https://github.com/electric-sql/meta/blob/main/CONTRIBUTING.md) and [Contributor License Agreement](https://github.com/electric-sql/meta/blob/main/CLA.md).

## Support

We have an [open community Discord](https://discord.gg/B7kHGwDcbj). If you’re interested in the project, please come and say hello and let us know if you have any questions or need any help or support getting things running.
