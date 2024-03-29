defmodule ElectricCli.Options do
  @moduledoc """
  Shared flags and options used across multiple commands.
  """
  alias ElectricCli.Util

  @default_flags []
  @default_options [
    root: [
      value_name: "DIR",
      short: "-r",
      long: "--root",
      help: "Path to the project directory. Defaults to the current directory.",
      default: "./",
      parser: :string
    ]
  ]

  def default_flags do
    @default_flags
  end

  def local_flags do
    [
      local: [
        long: "--local",
        help: "Disable authentication check for commands executed against the local console.",
        required: false
      ]
    ]
  end

  def merge_flags(flags \\ [], sort \\ true) when is_list(flags) and is_boolean(sort) do
    @default_flags
    |> Keyword.merge(flags)
    |> Util.optionally_sort(sort)
  end

  def default_options do
    @default_options
  end

  def merge_options(options \\ [], sort \\ true) when is_list(options) and is_boolean(sort) do
    @default_options
    |> Keyword.merge(options)
    |> Util.optionally_sort(sort)
  end

  def config_flags do
    [
      debug: [
        long: "--debug",
        help: "Enable debug mode.",
        required: false
      ],
      no_verify: [
        long: "--no-verify",
        help:
          "Skip verification that the `app` and `env` exist. " <>
            "(This avoids needing to authenticate).",
        required: false
      ]
    ]
  end

  def console_flags do
    [
      console_disable_ssl: [
        long: "--console-disable-ssl",
        help: "Connect to the console service without using SSL.",
        required: false
      ]
    ]
  end

  def console_options do
    [
      console_host: [
        long: "--console-host",
        value_name: "ADDRESS",
        help: "Console service host.",
        parser: :string
      ],
      console_port: [
        long: "--console-port",
        value_name: "PORT",
        help: "Console service port. Defaults to 443 if not specified.",
        parser: :integer
      ]
    ]
  end

  def directory_options(populate_defaults \\ true) do
    default_migrations_dir =
      case populate_defaults do
        true ->
          Application.fetch_env!(:electric_cli, :default_migrations_dir)

        false ->
          nil
      end

    default_output_dir =
      case populate_defaults do
        true ->
          Application.fetch_env!(:electric_cli, :default_output_dir)

        false ->
          nil
      end

    [
      migrations_dir: [
        value_name: "DIR",
        short: "-m",
        long: "--migrations-dir",
        help: "Path to the source directory where your migration files live.",
        parser: :string,
        default: default_migrations_dir
      ],
      output_dir: [
        value_name: "DIR",
        short: "-o",
        long: "--output-dir",
        help: "Path to the output directory where your autogenerated files live.",
        parser: :string,
        default: default_output_dir
      ]
    ]
  end

  def env_options do
    [
      env: [
        short: "-e",
        long: "--env",
        value_name: "ENV",
        help: "Name of the app environment (such as \"default\" or \"production\").",
        parser: :string
      ]
    ]
  end

  def replication_flags do
    [
      replication_disable_ssl: [
        long: "--replication-disable-ssl",
        help: "Connect to the replication service without using SSL.",
        required: false
      ]
    ]
  end

  def replication_options do
    [
      replication_host: [
        long: "--replication-host",
        value_name: "ADDRESS",
        help: "Replication service host.",
        parser: :string
      ],
      replication_port: [
        long: "--replication-port",
        value_name: "PORT",
        help: "Replication service port. Defaults to 443 if not specified.",
        parser: :integer
      ]
    ]
  end
end
