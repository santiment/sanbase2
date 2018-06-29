defmodule SanbaseWeb.Graphql.Helpers.UtilsTest do
  use SanbaseWeb.ConnCase, async: false

  alias SanbaseWeb.Graphql.Helpers.Utils

  defmodule StoreMock do
    def first_datetime(_measurement) do
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
      assert Utils.calibrate_interval(
               StoreMock,
               "some_measurement",
               context.from,
               context.to,
               "1000s",
               60
             ) == {:ok, context.from, context.to, "1000s"}
    end

    test "returns first date_time from the module and calculates the interval", context do
      {:ok, first_datetime} = StoreMock.first_datetime("")

      assert Utils.calibrate_interval(
               StoreMock,
               "some_measurement",
               context.from,
               context.to,
               "",
               60
             ) == {:ok, first_datetime, context.to, "1382s"}
    end

    test "returns date passed if it is after first_datetime and calculates the interval",
         context do
      from = DateTime.from_naive!(~N[2017-05-20 18:00:00], "Etc/UTC")

      assert Utils.calibrate_interval(
               StoreMock,
               "some_measurement",
               from,
               context.to,
               "",
               60
             ) == {:ok, from, context.to, "518s"}
    end
  end

  describe "#calibrate_interval_with_ma_interval/8" do
    test "returns 2 ma_interval when ma_base/interval is less then 2", context do
      {:ok, first_datetime} = StoreMock.first_datetime("")

      assert Utils.calibrate_interval_with_ma_interval(
               StoreMock,
               "some_measurement",
               context.from,
               context.to,
               "",
               60,
               "1500s"
             ) == {:ok, first_datetime, context.to, "1382s", 2}
    end

    test "calculates ma_interval when ma_base/interval is more then 2", context do
      {:ok, first_datetime} = StoreMock.first_datetime("")

      assert Utils.calibrate_interval_with_ma_interval(
               StoreMock,
               "some_measurement",
               context.from,
               context.to,
               "",
               60,
               "10000s"
             ) == {:ok, first_datetime, context.to, "1382s", 7}
    end
  end
end
