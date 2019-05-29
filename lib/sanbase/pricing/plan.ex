defmodule Sanbase.Pricing.Plan do
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query
  import Sanbase.Math, only: [to_integer: 1]

  alias Sanbase.Repo
  alias Sanbase.Pricing.{Product, Subscription}
  alias __MODULE__

  schema "plans" do
    field(:name, :string)
    field(:amount, :integer)
    field(:currency, :string)
    field(:interval, :string)
    field(:stripe_id, :string)
    field(:access, :map, default: %{})

    belongs_to(:product, Product)
    has_many(:subscriptions, Subscription, on_delete: :delete_all)
  end

  def changeset(%Plan{} = plan, attrs \\ %{}) do
    plan
    |> cast(attrs, [:stripe_id, :access])
  end

  def plans_with_metric(query) do
    from(
      p in Plan,
      where: fragment(~s(access @> ?), ^%{metrics: [query]})
    )
    |> Repo.all()
    |> Enum.map(&Map.get(&1, :name))
  end

  def by_id(plan_id) do
    Repo.get(__MODULE__, plan_id)
    |> Repo.preload(:product)
    |> update_stripe_id_if_not_present()
  end

  defp update_stripe_id_if_not_present(%__MODULE__{stripe_id: stripe_id} = plan)
       when is_nil(stripe_id) do
    plan
    |> create_stripe_plan()
    |> case do
      {:ok, stripe_plan} ->
        update_plan(plan, %{stripe_id: stripe_plan.id})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp update_stripe_id_if_not_present(%__MODULE__{stripe_id: stripe_id} = plan)
       when is_binary(stripe_id) do
    {:ok, plan}
  end

  defp create_stripe_plan(
         %__MODULE__{
           name: name,
           currency: currency,
           amount: amount,
           interval: interval,
           product: %Product{stripe_id: product_stripe_id}
         } = plan
       ) do
    Stripe.Plan.create(%{
      name: plan.name,
      currency: plan.currency,
      amount: amount,
      interval: interval,
      product: product_stripe_id
    })
  end

  defp update_plan(plan, params) do
    plan
    |> __MODULE__.changeset(params)
    |> Repo.update()
  end
end
