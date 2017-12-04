defmodule Sanbase.Notifications.CheckPrices.ComputeMovementsTest do
  use Sanbase.DataCase, async: true

  alias Sanbase.Notifications.CheckPrices.ComputeMovements
  alias Sanbase.Notifications.Notification
  alias Sanbase.Model.Project

  test "computing the movements when there are no prices for the project" do
    assert ComputeMovements.build_notification("Project", "usd", [], 5) == nil
  end

  test "computing the notifications when there are no changes in the price" do
    prices = [
      [DateTime.from_unix!(1510928574), 100],
      [DateTime.from_unix!(1510928575), 100],
      [DateTime.from_unix!(1510928576), 100],
    ]
    assert ComputeMovements.build_notification("Project", "usd", prices, 5) == nil
  end

  test "computing the notifications when the change is below the threshold" do
    prices = [
      [DateTime.from_unix!(1510928574), 101],
      [DateTime.from_unix!(1510928575), 100],
      [DateTime.from_unix!(1510928576), 104],
    ]
    assert ComputeMovements.build_notification("Project", "usd", prices, 5) == nil
  end

  test "computing the notifications when the change is above the threshold" do
    prices = [
      [DateTime.from_unix!(1510928574), 101],
      [DateTime.from_unix!(1510928575), 100],
      [DateTime.from_unix!(1510928576), 105],
    ]
    project = %Project{id: 1}

    {%Notification{}, 5.0, %Project{}} = ComputeMovements.build_notification(project, "usd", prices, 5)
  end

  test "computing the notifications when the change is negative and above threshold" do
    prices = [
      [DateTime.from_unix!(1510928574), 101],
      [DateTime.from_unix!(1510928575), 105],
      [DateTime.from_unix!(1510928576), 100],
    ]
    project = %Project{id: 1}

    {%Notification{}, -5.0, %Project{}} = ComputeMovements.build_notification(project, "usd", prices, 5)
  end
end
