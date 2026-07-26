# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :action_points, :scopes,
  user: [
    default: true,
    module: ActionPoints.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: ActionPoints.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :action_points,
  ecto_repos: [ActionPoints.Repo],
  generators: [timestamp_type: :utc_datetime]

# The Extractor port: real adapter is Claude; tests swap in a fake
config :action_points, :extractor, ActionPoints.Meetings.Extractor.Claude

# The Task Sink port: real adapter is Linear; tests swap in a fake
config :action_points, :task_sink, ActionPoints.Sinks.Linear

# Subtitle types for the Transcript upload — not in the MIME defaults
config :mime, :types, %{
  "text/vtt" => ["vtt"],
  "application/x-subrip" => ["srt"]
}

# Configures the endpoint
config :action_points, ActionPointsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: ActionPointsWeb.ErrorHTML, json: ActionPointsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ActionPoints.PubSub,
  live_view: [signing_salt: "3MY20CZ8"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :action_points, ActionPoints.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  action_points: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.7",
  action_points: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
