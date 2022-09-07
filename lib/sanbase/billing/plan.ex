defmodule Sanbase.Billing.Plan do
  @moduledoc """
  Module for managing billing plans that define the amount and billing cycle
  for subscriptions.
  We have plans with the same name but different interval (`month`, `year`) and amount.
  """
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias __MODULE__.CustomPlan
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
    field(:is_deprecated, :boolean)
    # plans that customers can't subscribe on their own
    field(:is_private, :boolean)
    # order first by `order` field, then by id
    field(:order, :integer)

    # if plan is custom, then the restrictions for it are read from the restrictions field
    field(:has_custom_restrictions, :boolean)
    embeds_one(:restrictions, CustomPlan.Restrictions, on_replace: :update)

    belongs_to(:product, Product)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
  end

  def changeset(%__MODULE__{} = plan, attrs \\ %{}) do
    plan
    |> cast(attrs, [
      :name,
      :product_id,
      :amount,
      :currency,
      :interval,
      :stripe_id,
      :is_deprecated,
      :is_private,
      :order,
      :has_custom_restrictions
    ])
    |> cast_embed(:restrictions, required: false, with: &CustomPlan.Restrictions.changeset/2)
    |> unique_constraint(:id, name: :plans_pkey)
  end

  def create_custom_api_plan(args) do
    args = %{
      name: Map.fetch!(args, :name),
      product_id: Map.fetch!(args, :product_id),
      amount: Map.fetch!(args, :amount),
      currency: Map.fetch!(args, :currency),
      interval: Map.fetch!(args, :interval),
      stripe_id: Map.get(args, :stripe_id),
      is_deprecated: false,
      is_private: true,
      order: Map.get(args, :order, 0),
      has_custom_restrictions: true,
      restrictions: Map.fetch!(args, :restrictions)
    }

    %__MODULE__{}
    |> changeset(args)
    |> Sanbase.Repo.insert()
  end

  def update_plan(plan, params) do
    plan
    |> changeset(params)
    |> Repo.update()
  end

  def list_custom_plans() do
    plans =
      from(
        p in __MODULE__,
        where: p.has_custom_restrictions == true
      )
      |> Repo.all()

    {:ok, plans}
  end

  def by_ids(plan_ids) when is_list(plan_ids) do
    from(p in __MODULE__, where: p.id in ^plan_ids)
    |> Repo.all()
  end

  def free_plan() do
    %__MODULE__{name: "FREE"}
  end

  @same_name_plans ["FREE", "BASIC", "PRO", "PRO_PLUS", "PREMIUM", "EXTENSION"]
  @enterprise_plans ["CUSTOM", "ENTERPRISE", "ENTERPRISE_BASIC", "ENTERPRISE_PLUS"]
  def plan_name(%__MODULE__{} = plan) do
    case plan.name do
      name when name in @same_name_plans -> name
      name when name in @enterprise_plans -> "CUSTOM"
      "ESSENTIAL" -> "BASIC"
      "CUSTOM_" <> _ = name -> name
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
end
