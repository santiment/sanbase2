defmodule Sanbase.Billing.Subscription.Timeseries do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Repo

  schema "subscription_timeseries" do
    field(:stats, :map)
    field(:subscriptions, {:array, :map})

    timestamps()
  end

  @doc false
  def changeset(timeseries, attrs) do
    timeseries
    |> cast(attrs, [:subscriptions, :stats])
    |> validate_required([:subscriptions, :stats])
  end

  def run do
    subscriptions = list()
    stats = stats(subscriptions)

    create(subscriptions, stats)
  end

  def create(subscriptions, stats) do
    changeset(%__MODULE__{}, %{subscriptions: subscriptions, stats: stats})
    |> Repo.insert()
  end

  def stats do
    list()
    |> stats()
  end

  def stats(subscriptions) do
    %{
      team_members: team_members(subscriptions) |> Enum.count(),
      active_and_paid: active_subscriptions(subscriptions) |> paid() |> Enum.count(),
      trialing: trialing_subscriptions(subscriptions) |> Enum.count(),
      other_status: other_status_subscriptions(subscriptions) |> Enum.count(),
      sanbase_active_and_paid:
        active_subscriptions(subscriptions)
        |> product_name_starts_with("Sanbase")
        |> paid()
        |> Enum.count(),
      san_api_active_and_paid:
        active_subscriptions(subscriptions)
        |> product_name_starts_with("SanAPI")
        |> paid()
        |> Enum.count()
    }
  end

  def list do
    all_subscriptions =
      list_all_subscriptions(
        [],
        %{limit: 50},
        expand: ["customer", "plan.product", "latest_invoice"]
      )
      |> extract_fields()
  end

  def list_all_subscriptions(subscriptions, opts \\ %{}, kw_list \\ []) do
    {:ok, new_subscriptions} = Stripe.Subscription.list(opts, kw_list)

    if new_subscriptions.data == [] do
      subscriptions
    else
      list_all_subscriptions(
        subscriptions ++ new_subscriptions.data,
        Map.put(opts, :starting_after, new_subscriptions.data |> List.last() |> Map.get(:id)),
        kw_list
      )
    end
  end

  def extract_fields(subscriptions) do
    Enum.map(subscriptions, fn subscription ->
      %{
        id: subscription.id,
        customer_id: subscription.customer.id,
        email: subscription.customer.email,
        status: subscription.status,
        plan_nickname: subscription.plan.nickname,
        product_name: subscription.plan.product.name,
        amount: subscription.plan.amount,
        latest_invoice_amount_due: subscription.latest_invoice.amount_due,
        metadata: subscription.metadata
      }
    end)
  end

  def active_subscriptions(subscriptions) do
    Enum.filter(subscriptions, fn subscription -> subscription.status == "active" end)
    |> non_team_members()
  end

  def trialing_subscriptions(subscriptions) do
    Enum.filter(subscriptions, fn subscription -> subscription.status == "trialing" end)
    |> non_team_members()
  end

  def other_status_subscriptions(subscriptions) do
    Enum.filter(subscriptions, fn subscription ->
      subscription.status not in ["active", "trialing"]
    end)
  end

  def product_name_starts_with(subscriptions, name) do
    Enum.filter(subscriptions, fn subscription ->
      String.starts_with?(subscription.product_name, name)
    end)
  end

  def team_members(subscriptions) do
    Enum.filter(subscriptions, fn subscription ->
      not is_nil(subscription.email) && String.ends_with?(subscription.email, "@santiment.net")
    end)
  end

  def non_team_members(subscriptions) do
    Enum.filter(subscriptions, fn subscription ->
      is_nil(subscription.email) || !String.ends_with?(subscription.email, "@santiment.net")
    end)
  end

  def paid(subscriptions) do
    Enum.filter(subscriptions, fn subscription -> subscription.latest_invoice_amount_due > 0 end)
  end

  def not_paid(subscriptions) do
    Enum.filter(subscriptions, fn subscription -> subscription.latest_invoice_amount_due == 0 end)
  end
end
