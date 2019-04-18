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
      use Phoenix.ConnTest
      import SanbaseWeb.Router.Helpers

      # The default endpoint for testing
      @endpoint SanbaseWeb.Endpoint
    end
  end

  setup tags do
    require Sanbase.CaseHelpers

    SanbaseWeb.Graphql.Cache.clear_all()

    Sanbase.CaseHelpers.checkout_shared(tags)
    conn = Phoenix.ConnTest.build_conn()

    staked_conn =
      SanbaseWeb.Graphql.TestHelpers.setup_jwt_auth(conn, Sanbase.Factory.insert(:staked_user))

    {:ok, conn: conn, staked_conn: staked_conn}
  end
end
