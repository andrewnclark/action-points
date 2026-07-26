defmodule ActionPointsWeb.PageController do
  use ActionPointsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
