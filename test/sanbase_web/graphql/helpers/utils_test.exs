defmodule SanbaseWeb.Graphql.Helpers.UtilsTest do
  use SanbaseWeb.ConnCase, async: true

  alias SanbaseWeb.Graphql.Helpers.CalibrateInterval

  defmodule StoreMock do
    def first_datetime(_slug) do
      {:ok, DateTime.from_naive!(~N[2017-05-15 18:00:00], "Etc/UTC")}
    end
  end

  setup do
    from = DateTime.from_naive!(~N[2017-05-13 18:00:00], "Etc/UTC")
    to = DateTime.from_naive!(~N[2017-05-23 18:00:00], "Etc/UTC")

    [from: from, to: to]
  end

  describe "#calibrate_interval/7" do
    test "returns original data if interval is specified", context do
      assert CalibrateInterval.calibrate(
               StoreMock,
               "some_slug",
               context.from,
               context.to,
               "1000s",
               60
             ) == {:ok, context.from, context.to, "1000s"}
    end

    test "returns first date_time from the module and calculates the interval", context do
      {:ok, first_datetime} = StoreMock.first_datetime("")

      assert CalibrateInterval.calibrate(
               StoreMock,
               "some_slug",
               context.from,
               context.to,
               "",
               60
             ) == {:ok, first_datetime, context.to, "1382s"}
    end

    test "returns date passed if it is after first_datetime and calculates the interval",
         context do
      from = DateTime.from_naive!(~N[2017-05-20 18:00:00], "Etc/UTC")

      assert CalibrateInterval.calibrate(
               StoreMock,
               "some_slug",
               from,
               context.to,
               "",
               60
             ) == {:ok, from, context.to, "518s"}
    end
  end
end
