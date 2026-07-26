defmodule ActionPointsWeb.RawBody do
  @moduledoc """
  A `Plug.Parsers` body reader that keeps the raw bytes of webhook requests in
  `conn.assigns.raw_body`. Signature verification needs the payload exactly as
  Stripe sent it — re-encoding parsed JSON does not round-trip — but caching
  every request body would be waste, so only `/webhooks` paths are kept.
  """

  def read_body(%Plug.Conn{path_info: ["webhooks" | _rest]} = conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {result, chunk, conn} when result in [:ok, :more] ->
        {result, chunk, update_in(conn.assigns[:raw_body], &((&1 || "") <> chunk))}

      other ->
        other
    end
  end

  def read_body(conn, opts), do: Plug.Conn.read_body(conn, opts)
end
