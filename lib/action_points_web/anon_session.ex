defmodule ActionPointsWeb.AnonSession do
  @moduledoc """
  Gives every visitor a random session token before any LiveView mounts.

  Extractions are keyed to this token, which is what lets an anonymous
  preview be persisted server-side (and later claimed at signup).
  """

  import Plug.Conn

  @session_key :anon_session_token

  def fetch_anon_session_token(conn, _opts) do
    if get_session(conn, @session_key) do
      conn
    else
      put_session(conn, @session_key, generate_token())
    end
  end

  defp generate_token do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
