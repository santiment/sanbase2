defmodule Sanbase.Notifications.CheckPrices.ComputeMovementsTest do
  use Sanbase.DataCase, async: false

  alias Sanbase.Notifications.CheckPrices.ComputeMovements
  alias Sanbase.Notifications.Notification
  alias Sanbase.Model.Project

  test "computing the movements when there are no prices for the project" do
    assert ComputeMovements.build_notification("Project", "USD", [], 5) == nil
  end

  test "computing the notifications when there are no changes in the price" do
    prices = [
      [DateTime.from_unix!(1_510_928_574), 100],
      [DateTime.from_unix!(1_510_928_575), 100],
      [DateTime.from_unix!(1_510_928_576), 100]
    ]

    assert ComputeMovements.build_notification("Project", "USD", prices, 5) == nil
  end

  test "computing the notifications when the change is below the threshold" do
    prices = [
      [DateTime.from_unix!(1_510_928_574), 101],
      [DateTime.from_unix!(1_510_928_575), 100],
      [DateTime.from_unix!(1_510_928_576), 104]
    ]

    assert ComputeMovements.build_notification("Project", "USD", prices, 5) == nil
  end

  test "computing the notifications when the change is above the threshold" do
    prices = [
      [DateTime.from_unix!(1_510_928_574), 101],
      [DateTime.from_unix!(1_510_928_575), 100],
      [DateTime.from_unix!(1_510_928_576), 105]
    ]

    project = %Project{id: 1}

    {%Notification{}, 5.0, %Project{}} =
      ComputeMovements.build_notification(project, "USD", prices, 5)
  end

  test "computing the notifications when the change is negative and above threshold" do
    prices = [
      [DateTime.from_unix!(1_510_928_574), 101],
      [DateTime.from_unix!(1_510_928_575), 105],
      [DateTime.from_unix!(1_510_928_576), 100]
    ]

    project = %Project{id: 1}

    {%Notification{}, -5.0, %Project{}} =
      ComputeMovements.build_notification(project, "USD", prices, 5)
  end
end
