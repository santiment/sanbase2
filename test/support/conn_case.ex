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

  defp next_integer_fun() do
    # Use the :counters module introduced in OTP 21.1.
    # In the same suite all calls to this function will
    # generate numbers increamented by 1
    atomic_counter = :counters.new(1, [])
    :counters.put(atomic_counter, 1, 1)

    fn ->
      value = :counters.get(atomic_counter, 1)
      :counters.add(atomic_counter, 1, 1)
      value
    end
  end

  setup tags do
    require Sanbase.CaseHelpers

    SanbaseWeb.Graphql.Cache.clear_all()

    Sanbase.CaseHelpers.checkout_shared(tags)

    conn = Phoenix.ConnTest.build_conn()

    product_and_plans = Sanbase.Billing.TestSeed.seed_products_and_plans()

    {:ok,
     conn: conn,
     product: Map.get(product_and_plans, :product),
     plans: Map.delete(product_and_plans, :product),
     next_integer: next_integer_fun()}
  end
end
