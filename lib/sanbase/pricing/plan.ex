defmodule Sanbase.Pricing.Plan do
  @moduledoc """
  Module for managing billing plans that define the amount and billing cycle
  for subscriptions.
  We have plans with the same name but different interval (`month`, `year`) and amount.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  alias Sanbase.Repo
  alias Sanbase.Pricing.{Product, Subscription}
  alias __MODULE__

  schema "plans" do
    field(:name, :string)
    # amount is in cents
    field(:amount, :integer)
    field(:currency, :string)
    # interval is one of `month` or `year`
    field(:interval, :string)
    field(:stripe_id, :string)
    field(:access, :map, default: %{})

    belongs_to(:product, Product)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
  end

  def changeset(%__MODULE__{} = plan, attrs \\ %{}) do
    plan
    |> cast(attrs, [:stripe_id, :access])
  end

  def by_id(plan_id) do
    Repo.get(__MODULE__, plan_id)
    |> Repo.preload(:product)
  end

  @doc """
  List all products with corresponding subscription plans
  """
  def product_with_plans do
    product_with_plans =
      Product
      |> Repo.all()
      |> Repo.preload(:plans)

    {:ok, product_with_plans}
  end

  @doc """
  Fetch all names of plans that give access to query.
  Fetching only with `interval`=`month` because we have yearly metrics with the same metrics
  and names.
  """
  def plans_with_metric(query) do
    from(
      p in Plan,
      where: p.interval == "month" and fragment(~s(access @> ?), ^%{metrics: [query]}),
      select: p.name
    )
    |> Repo.all()
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
