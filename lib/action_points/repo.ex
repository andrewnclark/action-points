defmodule ActionPoints.Repo do
  use Ecto.Repo,
    otp_app: :action_points,
    adapter: Ecto.Adapters.Postgres
end
