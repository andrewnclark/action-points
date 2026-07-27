defmodule ActionPointsWeb.LocalDate do
  @moduledoc """
  The visitor's own local date, as their browser supplied it through LiveView
  connect params (see `assets/js/app.js`). A plain date — never a time, never
  a timezone: the browser already knows what day it is where the visitor is,
  so nothing needs recomputing server-side.
  """

  import Phoenix.LiveView, only: [get_connect_params: 1]

  @doc """
  Reads the `local_date` connect param during mount. Returns nil when the
  socket is not connected, the param never arrived, or the browser sent
  something that isn't a date — callers fall back to the server's date.
  """
  def from_connect_params(socket) do
    with %{"local_date" => value} <- get_connect_params(socket),
         {:ok, date} <- Date.from_iso8601(to_string(value)) do
      date
    else
      _missing_or_junk -> nil
    end
  end
end
