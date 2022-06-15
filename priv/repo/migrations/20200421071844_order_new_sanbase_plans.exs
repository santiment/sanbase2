defmodule Sanbase.Repo.Migrations.OrderNewSanbasePlans do
  use Ecto.Migration

  import Ecto.Query

  alias Sanbase.Billing.Plan
  alias Sanbase.Repo

  def up do
    setup()

    order_list = [11, 201, 14, 202, 17, 12, 13, 15, 16]
    len = length(order_list)

    order_list
    |> Enum.with_index()
    |> Enum.into(%{}, fn {item, idx} -> {item, len - idx} end)
    |> Enum.sort_by(fn {_, v} -> v end, &>=/2)
    |> Enum.each(fn {plan_id, order} ->
      Repo.get(Plan, plan_id)
      |> Plan.changeset(%{order: order})
      |> Repo.update()
    end)
  end

  def down do
    execute("""
    UPDATE plans SET "order"=0 where product_id = 2
    """)
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:stripity_stripe)
  end
end
