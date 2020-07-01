defmodule Sanbase.Signal.TriggerDailyActiveAddressesHistoryTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers

  alias Sanbase.Signal.UserTrigger

  setup_all_with_mocks([
    {Sanbase.Metric, [:passthrough],
     [timeseries_data: fn "daily_active_addresses", _, _, _, _, _ -> {:ok, daa_resp()} end]}
  ]) do
    []
  end

  setup do
    project = insert(:random_erc20_project, %{ticker: "SAN", slug: "santiment"})

    [project: project]
  end

  test "percent change up 200", %{project: project} do
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

  test "percent change up 200 with small cooldown", %{project: project} do
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

  test "percent change down 50", %{project: project} do
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

  test "absolute value above 100", %{project: project} do
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

  test "absolute value below 40", %{project: project} do
    trigger_settings = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: "telegram",
      time_window: "2d",
      operation: %{below: 40}
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
             DateTime.to_iso8601(dt) == "2018-11-21T00:00:00Z"
           end)
           |> Map.get(:triggered?) == true
  end

  test "absolute value below 40 with small cooldown", %{project: project} do
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

  test "percent change up 100% and absolute value above 50", %{project: project} do
    trigger_settings = %{
      type: "daily_active_addresses",
      target: %{slug: project.slug},
      channel: "telegram",
      time_window: "2d",
      operation: %{all_of: [%{above: 50}, %{percent_up: 100}]}
    }

    trigger = %{settings: trigger_settings, cooldown: "12h"}

    {:ok, points} = UserTrigger.historical_trigger_points(trigger)

    assert Enum.filter(points, & &1.triggered?) |> length() == 4
    assert Enum.filter(points, &(!&1.triggered?)) |> length() == 6
    assert length(points) == 10

    assert points
           |> Enum.find(fn %{datetime: dt} ->
             DateTime.to_iso8601(dt) == "2018-11-17T00:00:00Z"
           end)
           |> Map.get(:triggered?) == true

    assert points
           |> Enum.find(fn %{datetime: dt} ->
             DateTime.to_iso8601(dt) == "2018-11-19T00:00:00Z"
           end)
           |> Map.get(:triggered?) == true

    assert points
           |> Enum.find(fn %{datetime: dt} ->
             DateTime.to_iso8601(dt) == "2018-11-22T00:00:00Z"
           end)
           |> Map.get(:triggered?) == true

    assert points
           |> Enum.find(fn %{datetime: dt} ->
             DateTime.to_iso8601(dt) == "2018-11-23T00:00:00Z"
           end)
           |> Map.get(:triggered?) == true
  end

  defp daa_resp() do
    [
      %{datetime: ~U[2018-11-16 00:00:00Z], value: 20},
      %{datetime: ~U[2018-11-17 00:00:00Z], value: 200},
      %{datetime: ~U[2018-11-18 00:00:00Z], value: 25},
      %{datetime: ~U[2018-11-19 00:00:00Z], value: 60},
      %{datetime: ~U[2018-11-20 00:00:00Z], value: 30},
      %{datetime: ~U[2018-11-21 00:00:00Z], value: 20},
      %{datetime: ~U[2018-11-22 00:00:00Z], value: 76},
      %{datetime: ~U[2018-11-23 00:00:00Z], value: 180},
      %{datetime: ~U[2018-11-24 00:00:00Z], value: 50},
      %{datetime: ~U[2018-11-25 00:00:00Z], value: 60},
      %{datetime: ~U[2018-11-26 00:00:00Z], value: 70}
    ]
  end
end
