defmodule Sanbase.Billing.Plan do
  @moduledoc """
  Module for managing billing plans that define the amount and billing cycle
  for subscriptions.
  We have plans with the same name but different interval (`month`, `year`) and amount.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Billing.{Product, Subscription}

  @plans_order [free: 0, basic: 1, pro: 2, premium: 3, custom: 4]
  @plans Keyword.keys(@plans_order)

  def plans(), do: @plans
  def plans_order(), do: @plans_order
  def sort_plans(plans), do: Enum.sort_by(plans, fn plan -> Keyword.get(@plans_order, plan) end)

  schema "plans" do
    field(:name, :string)
    # amount is in cents
    field(:amount, :integer)
    field(:currency, :string)
    # interval is one of `month` or `year`
    field(:interval, :string)
    field(:stripe_id, :string)

    # there might be still customers on this plan, but new subscriptions should be disabled.
    field(:is_deprecated, :boolean, default: false)

    # plans that customers can't subscribe on their own
    field(:is_private, :boolean, default: false)

    # order first by `order` field, then by id
    field(:order, :integer, default: 0)

    belongs_to(:product, Product)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
  end

  def changeset(%__MODULE__{} = plan, attrs \\ %{}) do
    plan
    |> cast(attrs, [:amount, :name, :stripe_id, :is_deprecated, :is_private, :order])
  end

  def by_ids(plan_ids) when is_list(plan_ids) do
    from(p in __MODULE__, where: p.id in ^plan_ids)
    |> Repo.all()
  end

  def free_plan() do
    %__MODULE__{name: "FREE"}
  end

  @plan_same_name ["FREE", "BASIC", "PRO", "PRO_PLUS", "PREMIUM", "CUSTOM", "EXTENSION"]
  def plan_name(%__MODULE__{} = plan) do
    case plan do
      %{name: name} when name in @plan_same_name -> name
      %{name: "ESSENTIAL"} -> "BASIC"
      %{name: "ENTERPRISE" <> _rest} -> "CUSTOM"
      %{name: "CUSTOM_" <> _ = name} -> name
    end
  end

  def plan_name(_), do: "FREE"

  def plan_full_name(plan) do
    plan = plan |> Repo.preload(:product)
    "#{plan.product.name} / #{plan.name}"
  end

  def by_id(plan_id) do
    Repo.get(__MODULE__, plan_id)
    |> Repo.preload(:product)
  end

  def by_stripe_id(stripe_id) do
    Repo.get_by(__MODULE__, stripe_id: stripe_id)
    |> Repo.preload(:product)
  end

  @doc """
  List all products with corresponding subscription plans
  """
  def product_with_plans do
    product_with_plans =
      Product
      |> Repo.all()
      |> Repo.preload(plans: from(p in __MODULE__, order_by: [desc: p.order, asc: p.id]))

    {:ok, product_with_plans}
  end

  @doc """
  If a plan doesn't have filled `stripe_id` - create a plan in Stripe and update with the received
  `stripe_id`
  """
  def maybe_create_plan_in_stripe(%__MODULE__{stripe_id: stripe_id} = plan)
      when is_nil(stripe_id) do
    plan
    |> Sanbase.StripeApi.create_plan()
    |> case do
      {:ok, stripe_plan} ->
        update_plan(plan, %{stripe_id: stripe_plan.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def maybe_create_plan_in_stripe(%__MODULE__{stripe_id: stripe_id} = plan)
      when is_binary(stripe_id) do
    {:ok, plan}
  end

  defp update_plan(plan, params) do
    plan
    |> changeset(params)
    |> Repo.update()
  end
end
