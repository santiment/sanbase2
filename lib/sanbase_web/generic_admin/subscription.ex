defmodule SanbaseWeb.GenericAdmin.Subscription do
  def schema_module, do: Sanbase.Billing.Subscription

  def resource do
    %{
      preloads: [:user, plan: [:product]],
      actions: [:edit],
      funcs: %{
        plan_id: &__MODULE__.plan_func/1,
        user_id: &__MODULE__.user_func/1
      }
    }
  end

  def has_many(_subscription) do
    []
  end

  def belongs_to(_subscription) do
    []
  end

  def plan_func(row) do
    link_content = "#{row.plan.product.name}/#{row.plan.name}"
    href("plans", row.plan_id, link_content)
  end

  def user_func(row) do
    link_content = row.user.email || row.user.username || row.user.id
    href("users", row.user_id, link_content)
  end

  def href(resource, id, label) do
    relative_url =
      SanbaseWeb.Router.Helpers.generic_path(SanbaseWeb.Endpoint, :show, id, resource: resource)

    Phoenix.HTML.Link.link(label, to: relative_url, class: "text-blue-600 hover:text-blue-800")
  end
end

defmodule SanbaseWeb.GenericAdmin.Plan do
  def schema_module, do: Sanbase.Billing.Plan

  def resource do
    %{
      preloads: [:product],
      index_fields: [
        :id,
        :product_id,
        :name,
        :amount,
        :currency,
        :interval,
        :stripe_id,
        :is_deprecated,
        :is_private,
        :order
      ],
      edit_fields: [:name, :amount, :stripe_id, :is_deprecated, :is_private, :order],
      actions: [:edit],
      funcs: %{
        product_id: &SanbaseWeb.GenericAdmin.Product.product_link/1,
        restrictions: fn plan ->
          if(plan.restrictions,
            do: Map.from_struct(plan.restrictions) |> Jason.encode!(),
            else: ""
          )
        end
      }
    }
  end
end

defmodule SanbaseWeb.GenericAdmin.Product do
  def schema_module, do: Sanbase.Billing.Product

  def resource do
    %{
      actions: []
    }
  end

  def product_link(row) do
    SanbaseWeb.GenericAdmin.Subscription.href("products", row.product_id, row.product.name)
  end
end

defmodule SanbaseWeb.GenericAdmin.PromoTrial do
  import Ecto.Query

  alias Sanbase.Billing.Subscription.PromoTrial

  def schema_module, do: PromoTrial

  def resource do
    %{
      preloads: [:user],
      actions: [:new],
      new_fields: [:user, :trial_days, :plans],
      index_fields: [:id, :user_id, :plans, :trial_days, :created_at, :updated_at],
      field_types: %{
        plans: :multiselect
      },
      collections: %{
        plans: PromoTrial.plan_id_name_map() |> Enum.map(fn {id, name} -> {name, id} end)
      },
      belongs_to_fields: %{
        user: %{
          query: from(u in Sanbase.Accounts.User, order_by: [desc: u.id]),
          transform: fn rows -> Enum.map(rows, &{&1.email, &1.id}) end,
          resource: "users",
          search_fields: [:email, :username]
        }
      },
      funcs: %{
        user_id: &SanbaseWeb.GenericAdmin.User.user_link/1,
        plans: fn promo_trial -> Enum.join(promo_trial.plans, ",") end
      }
    }
  end
end
