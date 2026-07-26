import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/action_points start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :action_points, ActionPointsWeb.Endpoint, server: true
end

# Read in every environment; the Claude adapter refuses to run without a key,
# and tests never reach it (the Extractor port is faked there).
if api_key = System.get_env("ANTHROPIC_API_KEY") do
  config :action_points, ActionPoints.Meetings.Extractor.Claude, api_key: api_key
end

# Read in every environment: Stripe test keys in dev, live keys later as a
# config change (story 43). Tests never reach it — the payment port is faked.
if stripe_secret_key = System.get_env("STRIPE_SECRET_KEY") do
  config :action_points, ActionPoints.Billing.Stripe,
    api_key: stripe_secret_key,
    webhook_secret: System.get_env("STRIPE_WEBHOOK_SECRET")
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :action_points, ActionPoints.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  sink_encryption_key =
    System.get_env("SINK_ENCRYPTION_KEY") ||
      raise """
      environment variable SINK_ENCRYPTION_KEY is missing.
      It encrypts stored Task Sink API keys at rest.
      You can generate one by calling: openssl rand -base64 32
      """

  config :action_points, ActionPoints.Vault, key: sink_encryption_key

  # Magic-link login is the only way in, so the mailer must deliver somehow.
  # With a RESEND_API_KEY we send real email; without one we log the full
  # message — link included — so it can be read with `fly logs`. That is a
  # friends-test stopgap, not a launch posture: links in logs are visible to
  # anyone with Fly access to this org.
  if resend_api_key = System.get_env("RESEND_API_KEY") do
    config :action_points, ActionPoints.Mailer,
      adapter: Swoosh.Adapters.Resend,
      api_key: resend_api_key
  else
    config :action_points, ActionPoints.Mailer,
      adapter: Swoosh.Adapters.Logger,
      log_full_email: true,
      level: :info
  end

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :action_points, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :action_points, ActionPointsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :action_points, ActionPointsWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :action_points, ActionPointsWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :action_points, ActionPoints.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
