defmodule ActionPointsWeb.ErrorHTMLTest do
  @moduledoc """
  The two pages nobody is meant to see. They are checked for the same things as
  every other screen: that they say what happened in the product's own voice and
  offer a way onward, and that they arrive as a real page of the design system
  rather than as Phoenix's bare status text.
  """

  use ActionPointsWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  describe "the 404 page" do
    test "names what happened and offers the way back" do
      html = render_to_string(ActionPointsWeb.ErrorHTML, "404", "html", [])

      assert element?(html, "#error-page")
      assert element?(html, "#error-page-home[href='/']")
      assert text(html) =~ "That page isn't here."
    end
  end

  describe "the 500 page" do
    test "owns the failure and offers the way back" do
      html = render_to_string(ActionPointsWeb.ErrorHTML, "500", "html", [])

      assert element?(html, "#error-page-home[href='/']")
      assert text(html) =~ "Something broke at our end."
    end
  end

  describe "a status with no copy of its own" do
    test "still arrives as a designed page rather than a word" do
      html = render_to_string(ActionPointsWeb.ErrorHTML, "422", "html", [])

      assert element?(html, "#error-page-home[href='/']")
      assert text(html) =~ "422"
      # Whatever Plug calls the status, stated as a sentence rather than dumped
      # as the bare word Phoenix would have served.
      assert text(html) =~ Plug.Conn.Status.reason_phrase(422) <> "."
    end
  end

  describe "an error served through the endpoint" do
    test "arrives as a full page of the design system, not bare status text",
         %{conn: conn} do
      conn = get(conn, "/no-such-page")

      assert conn.status == 404

      # The stylesheet and the theme script are what make an error page look
      # like the app: without the root layout, Phoenix serves "Not Found" as
      # unstyled text and the facelift stops at the last working route.
      assert element?(conn.resp_body, "head link[href*='/assets/css/app.css']")
      assert element?(conn.resp_body, "#error-page")
    end
  end

  defp element?(html, selector) do
    html |> LazyHTML.from_document() |> LazyHTML.query(selector) |> Enum.any?()
  end

  defp text(html), do: html |> LazyHTML.from_document() |> LazyHTML.text()
end
