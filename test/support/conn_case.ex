defmodule SanbaseWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common datastructures and query the data layer.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import SanbaseWeb.Router.Helpers

      # The default endpoint for testing
      @endpoint SanbaseWeb.Endpoint
    end
  end

  setup tags do
    require Sanbase.CaseHelpers

    SanbaseWeb.Graphql.Cache.clear_all()
    Sanbase.Cache.clear_all()

    Sanbase.CaseHelpers.checkout_shared(tags)

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.put_req_header("origin", "https://app.santiment.net")

    product_and_plans = Sanbase.Billing.TestSeed.seed_products_and_plans()

    {:ok,
     not_logged_conn: conn,
     conn: conn,
     product: Map.get(product_and_plans, :product),
     plans: Map.delete(product_and_plans, :product),
     next_integer: fn -> :erlang.unique_integer([:monotonic, :positive]) end}
  end
end
