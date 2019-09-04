defmodule Sanbase.Signal.TriggerDailyActiveAddressesHistoryTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.DateTimeUtils

  alias Sanbase.Signal.UserTrigger

  setup do
    project =
      insert(:project, %{
        ticker: "SAN",
        slug: "santiment",
        main_contract_address: "0x123"
      })

    [project: project]
  end

  test "percent change up 200", %{project: project} do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok, daa_resp()}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: %{slug: project.slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{percent_up: 200.0}
      }

      trigger = %{settings: trigger_settings, cooldown: "1d"}

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      assert Enum.filter(points, & &1.triggered?) |> length() == 2
      assert Enum.filter(points, &(!&1.triggered?)) |> length() == 8
      assert length(points) == 10

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-17T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-22T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true
    end
  end

  test "percent change up 200 with small cooldown", %{project: project} do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok, daa_resp()}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: %{slug: project.slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{percent_up: 200.0}
      }

      trigger = %{settings: trigger_settings, cooldown: "1h"}

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      assert Enum.filter(points, & &1.triggered?) |> length() == 2
      assert Enum.filter(points, &(!&1.triggered?)) |> length() == 8
      assert length(points) == 10

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-17T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-22T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true
    end
  end

  test "percent change down 50", %{project: project} do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok, daa_resp()}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: %{slug: project.slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{percent_down: 50.0}
      }

      trigger = %{settings: trigger_settings, cooldown: "1d"}

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      assert Enum.filter(points, & &1.triggered?) |> length() == 3
      assert Enum.filter(points, &(!&1.triggered?)) |> length() == 7
      assert length(points) == 10

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-18T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-20T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-24T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true
    end
  end

  test "absolute value above 100", %{project: project} do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok, daa_resp()}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: %{slug: project.slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{above: 100}
      }

      trigger = %{settings: trigger_settings, cooldown: "1d"}

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      assert Enum.filter(points, & &1.triggered?) |> length() == 2
      assert Enum.filter(points, &(!&1.triggered?)) |> length() == 8
      assert length(points) == 10

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-17T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-23T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true
    end
  end

  test "absolute value below 40", %{project: project} do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok, daa_resp()}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: %{slug: project.slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{below: 40}
      }

      trigger = %{settings: trigger_settings, cooldown: "1d"}

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      assert Enum.filter(points, & &1.triggered?) |> length() == 2
      assert Enum.filter(points, &(!&1.triggered?)) |> length() == 8
      assert length(points) == 10

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-18T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-20T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true
    end
  end

  test "absolute value below 40 with small cooldown", %{project: project} do
    with_mock Sanbase.Clickhouse.Erc20DailyActiveAddresses,
      average_active_addresses: fn _, _, _, _ ->
        {:ok, daa_resp()}
      end do
      trigger_settings = %{
        type: "daily_active_addresses",
        target: %{slug: project.slug},
        channel: "telegram",
        time_window: "2d",
        operation: %{below: 40}
      }

      trigger = %{settings: trigger_settings, cooldown: "12h"}

      {:ok, points} = UserTrigger.historical_trigger_points(trigger)

      assert Enum.filter(points, & &1.triggered?) |> length() == 3
      assert Enum.filter(points, &(!&1.triggered?)) |> length() == 7
      assert length(points) == 10

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-18T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-20T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true

      assert points
             |> Enum.find(fn %{datetime: dt} ->
               DateTime.to_iso8601(dt) == "2018-11-21T00:00:00Z"
             end)
             |> Map.get(:triggered?) == true
    end
  end

  defp daa_resp() do
    [
      %{datetime: from_iso8601!("2018-11-16T00:00:00Z"), active_addresses: 20},
      %{datetime: from_iso8601!("2018-11-17T00:00:00Z"), active_addresses: 200},
      %{datetime: from_iso8601!("2018-11-18T00:00:00Z"), active_addresses: 25},
      %{datetime: from_iso8601!("2018-11-19T00:00:00Z"), active_addresses: 60},
      %{datetime: from_iso8601!("2018-11-20T00:00:00Z"), active_addresses: 30},
      %{datetime: from_iso8601!("2018-11-21T00:00:00Z"), active_addresses: 20},
      %{datetime: from_iso8601!("2018-11-22T00:00:00Z"), active_addresses: 76},
      %{datetime: from_iso8601!("2018-11-23T00:00:00Z"), active_addresses: 180},
      %{datetime: from_iso8601!("2018-11-24T00:00:00Z"), active_addresses: 50},
      %{datetime: from_iso8601!("2018-11-25T00:00:00Z"), active_addresses: 60},
      %{datetime: from_iso8601!("2018-11-26T00:00:00Z"), active_addresses: 70}
    ]
  end
end
