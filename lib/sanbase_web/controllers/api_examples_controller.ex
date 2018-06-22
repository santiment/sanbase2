defmodule SanbaseWeb.ApiExamplesController do
  use SanbaseWeb, :controller

  alias SanbaseWeb.ApiExamplesView

  def api_examples(conn, _params) do
    conn
    |> put_layout({ApiExamplesView, "apiexample.html"})
    |> render(:apiexample_view)
  end
end
