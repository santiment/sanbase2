defmodule SanbaseWeb.ApiDocsController do
  use SanbaseWeb, :controller

  alias SanbaseWeb.ApiDocsView

  def api_examples(conn, _params) do
    conn
    |> put_layout({ApiDocsView, "apiexample.html"})
    |> render(:apiexample_view)
  end
end
