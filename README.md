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


## Migrations command

The `migrations` command lets you create new migrations, build electrified javascript distributions of the migrations 
to use in your project, and sync your migrations to our cloud service.

### init
`migrations init APP_ID [--dir MIGRATIONS_DIR]`

Creates a new folder for migrations in your current directory called 'migrations' and adds a new migration 
folder to it with a name automatically derived from the current time in UTC and the title `init` e.g. `20221116162204816_init`

Inside this folder will be a file called `migration.sql`. You should write your initial SQLite DDL SQL into this file.

The APP_ID you give should be the slug of the app previous created in the web console. 
You give it once here and the CLI stores it in the `migrations/manifest.json` so you don't have to keep re-typing it.

The optional `MIGRATIONS_DIR` allows you to create the migration folder somewhere other than the current working directory.

`MIGRATIONS_DIR` must end with the folder name `migrations`

### app
`migrations app APP_ID [--dir MIGRATIONS_DIR]`

Changes the stored `APP_ID` that is used by all the other CLI migrations commands.

The optional `MIGRATIONS_DIR` allows you to specify which migration directory to use other than one in the 
current working directory.

###new
`migrations new [--help] [--dir MIGRATIONS_DIR] MIGRATION_TITLE`

MIGRATION_TITLE should be a short human readable description of the new migration.

This adds a new migration to the `migrations` folder with a name automatically derived from the current
time in UTC and the given title.

The optional `MIGRATIONS_DIR` allows you to specify which migration directory to use other than one in the 
current working directory.

###build
`migrations build [--help] [--postgres] [--satellite] [--dir MIGRATIONS_DIR]`

Builds a javascript file at `dist/index.js` that contains all your migrations with Electric DB's added 
DDL and some metadata.  

The metadata in this file will have a `"env": "local" to indicate the it was built from your local files
rather that one of the named app environments.

Add this file to your mobile or web project to configure your SQLite database.

The optional `MIGRATIONS_DIR` allows you to specify which migration directory to use other than one in the 
current working directory.

The optional flag `--postgres` will also build a `postgres.sql` file in each migrations' folder with the PostgreSQL

The optional flag `--satellite` will also build a `satellite.sql` file in each migrations' folder.

###sync
`migrations sync [--env ENVIRONMENT_NAME] [--dir MIGRATIONS_DIR]`

Synchronises changes you have made to migration SQL files in your local `migrations` folder up to the Electric SQl servers, 
and builds a new javascript file at `dist/index.js` that matches the newly synchronised set of migrations.

The metadata in this file will have a `"env": ENVIRONMENT_NAME to indicate that it was built directly from and matches
the named app environment.

By default this will sync to the `default` environment for your app. If you want to use a different one give its name 
with `--env ENVIRONMENT_NAME`

If the app environment on our servers already has a migration with the same name but different sha256 then this 
synchronisation will fail because a migration cannot be modified once it has been applied. 
If this happens you have two options, either revert the local changes you have made to the conflicted migration using 
the `revert` command below or, if you are working in a development environment that you are happy to reset, 
you can reset the whole environment's DB using the web control panel.

Also if a migration has a name that is lower in sort order than one already applied on the server this sync will fail.

The optional `MIGRATIONS_DIR` allows you to specify which migration directory to use other than one in the 
current working directory.

###list
`migrations list [--help] [--dir MIGRATIONS_DIR]`

Will show a list of all the migrations and their status in every env in the app.

The optional `MIGRATIONS_DIR` allows you to specify which migration directory to use other than one in the 
current working directory.

### revert
`migrations revert [--help] [--dir MIGRATIONS_DIR] [--env ENVIRONMENT_NAME] MIGRATION_NAME`

This will copy the named migration from the Electric SQL server to replace the local one. 

By default this will use the `default` environment, if you want to use a different one you can specify it with 
`--env ENVIRONMENT_NAME`

The optional `MIGRATIONS_DIR` allows you to specify which migration directory to use other than one in the 
current working directory.