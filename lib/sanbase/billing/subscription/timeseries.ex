defmodule Sanbase.Billing.Subscription.Timeseries do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Utils.Config
  alias Sanbase.Repo

  schema "subscription_timeseries" do
    field(:stats, :map)
    field(:subscriptions, {:array, :map})

    timestamps()
  end

  @doc false
  def changeset(timeseries, attrs) do
    timeseries
    |> cast(attrs, [:subscriptions, :stats, :inserted_at])
    |> validate_required([:stats])
  end

  def run do
    # don't run on stage
    if Config.module_get(Sanbase, :deployment_env) == "stage" do
      :ok
    else
      subscriptions = list_active_subs()
      stats = stats(subscriptions)

      create(subscriptions, stats)
    end
  end

  def run_fill_history(start_date, end_date) do
    start_dt = DateTime.new!(start_date, ~T[00:00:00])
    subscriptions = list_canceled_subs(start_dt) ++ list_active_subs()
    fill_history(subscriptions, start_date, end_date)
  end

  def create(subscriptions, stats) do
    changeset(%__MODULE__{}, %{subscriptions: subscriptions, stats: stats})
    |> Repo.insert()
  end

  def create_historical(subscriptions, stats, dt) do
    changeset(%__MODULE__{}, %{subscriptions: subscriptions, stats: stats, inserted_at: dt})
    |> Repo.insert()
  end

  def format_subscriptions(subscriptions) do
    subscriptions
    |> Enum.map(fn map ->
      Enum.into(map, %{}, fn {k, v} ->
        k = String.to_existing_atom(k)

        v =
          if k in [:start_date, :end_date, :trial_start, :trial_end] and not is_nil(v) do
            Sanbase.DateTimeUtils.from_iso8601!(v)
          else
            v
          end

        {k, v}
      end)
    end)
  end

  def stats do
    list_active_subs()
    |> stats()
  end

  def fill_history(subscriptions, start_date, end_date) do
    Sanbase.DateTimeUtils.generate_dates_inclusive(start_date, end_date)
    |> Enum.each(fn date ->
      dt = DateTime.new!(date, ~T[00:00:00])
      stats = stats(subscriptions, dt)
      active_subs = historical_active(subscriptions, dt) |> non_team_members() |> paid()
      create_historical(active_subs, stats, dt)
    end)
  end

  def stats(subscriptions, date) do
    %{
      team_members: historical_active(subscriptions, date) |> team_members() |> Enum.count(),
      active_and_paid:
        historical_active(subscriptions, date) |> non_team_members() |> paid() |> Enum.count(),
      trialing: historical_trialing(subscriptions, date) |> non_team_members() |> Enum.count(),
      sanbase_active_and_paid:
        historical_active(subscriptions, date)
        |> non_team_members()
        |> paid()
        |> product_name_starts_with("Sanbase")
        |> Enum.count(),
      san_api_active_and_paid:
        historical_active(subscriptions, date)
        |> non_team_members()
        |> paid()
        |> product_name_starts_with("SanAPI")
        |> Enum.count()
    }
  end

  def stats(subscriptions) do
    stats = %{
      liquidity: get_active_liquidity_subscriptions_count(),
      sanr_nft: get_active_sanr_nft_subscriptions_count(),
      burning_nft: get_active_burning_nft_subscriptions_count(),
      team_members: team_members(subscriptions) |> Enum.count(),
      active_and_paid: active_subscriptions(subscriptions) |> paid() |> Enum.count(),
      trialing: trialing_subscriptions(subscriptions) |> Enum.count(),
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

    stats
    |> Map.put(
      :total_sanbase_active_and_paid,
      stats.sanbase_active_and_paid + stats.liquidity + stats.sanr_nft + stats.burning_nft
    )
  end

  def get_active_liquidity_subscriptions_count do
    from(s in Sanbase.Billing.Subscription,
      where: s.type == :liquidity and s.status == :active
    )
    |> Sanbase.Repo.aggregate(:count)
  end

  def get_active_sanr_nft_subscriptions_count do
    from(s in Sanbase.Billing.Subscription,
      where: s.type == :sanr_points_nft and s.status == :active
    )
    |> Sanbase.Repo.aggregate(:count)
  end

  def get_active_burning_nft_subscriptions_count do
    from(s in Sanbase.Billing.Subscription,
      where: s.type == :burning_nft and s.status == :active
    )
    |> Sanbase.Repo.aggregate(:count)
  end

  def list_active_subs do
    list_all_subscriptions(
      [],
      %{limit: 50},
      expand: ["data.customer", "data.items.data.price", "data.latest_invoice"]
    )
  end

  def list_canceled_subs(start_date) do
    list_all_subscriptions(
      [],
      %{
        status: "canceled",
        limit: 50,
        current_period_end: %{gte: DateTime.to_unix(start_date)}
      },
      expand: ["data.customer", "data.items.data.price", "data.latest_invoice"]
    )
  end

  def list_all_subscriptions(subscriptions, opts \\ %{}, kw_list \\ []) do
    {:ok, new_subscriptions} = fetch_subs(opts, kw_list, 1)

    if new_subscriptions.data == [] do
      subscriptions
    else
      list_all_subscriptions(
        subscriptions ++ extract_fields(new_subscriptions.data),
        Map.put(opts, :starting_after, new_subscriptions.data |> List.last() |> Map.get(:id)),
        kw_list
      )
    end
  end

  def fetch_subs(_, _, 5), do: {:error, "Cannot fetch subscriptions"}

  def fetch_subs(opts, kw_list, attempt) do
    case Sanbase.StripeApi.list_subscriptions(opts, kw_list) do
      {:ok, subscriptions} ->
        {:ok, subscriptions}

      {:error, %Stripe.Error{message: _reason}} ->
        fetch_subs(opts, kw_list, attempt + 1)
    end
  end

  def extract_fields(subscriptions) do
    subscriptions
    |> Enum.reject(fn subscription -> is_nil(plan(subscription)) end)
    |> Enum.map(fn subscription ->
      %{
        id: subscription.id,
        customer_id: subscription.customer.id,
        email: subscription.customer.email,
        status: subscription.status,
        plan_nickname: plan(subscription).nickname,
        product_name: plan(subscription).product |> product_name(),
        amount: plan(subscription).unit_amount,
        latest_invoice_amount_due: latest_invoice_amount(subscription, :amount_due),
        latest_invoice_amount_paid: latest_invoice_amount(subscription, :amount_paid),
        metadata: subscription.metadata,
        start_date: subscription.start_date |> format_dt(:start),
        end_date: subscription.ended_at |> format_dt(:end),
        trial_start: subscription.trial_start |> format_dt(:start),
        trial_end: subscription.trial_end |> format_dt(:end)
      }
    end)
  end

  defp plan(subscription) do
    (subscription.items.data |> hd).price
  end

  def product_name(stripe_product_id) do
    %{
      "prod_FJtAemBs4HJ1P3" => "SanAPI by Santiment",
      "prod_FVVljrXENI3MFQ" => "Sanbase by Santiment"
    }
    |> Map.get(stripe_product_id, stripe_product_id)
  end

  defp latest_invoice_amount(subscription, field) do
    case subscription.latest_invoice do
      %Stripe.Invoice{} = invoice -> Map.get(invoice, field)
      _ -> nil
    end
  end

  def format_dt(nil, _) do
    nil
  end

  def format_dt(unix, :start) do
    unix |> DateTime.from_unix!() |> Timex.beginning_of_day()
  end

  def format_dt(unix, :end) do
    unix |> DateTime.from_unix!() |> Timex.end_of_day()
  end

  def between?(date, start_date, end_date) do
    DateTime.compare(date, start_date) in [:gt, :eq] and
      DateTime.compare(date, end_date) in [:lt, :eq]
  end

  def active_subscriptions(subscriptions) do
    Enum.filter(subscriptions, fn subscription ->
      subscription.status in ["active", "past_due"]
    end)
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
    Enum.filter(subscriptions, fn subscription -> subscription.latest_invoice_amount_paid > 0 end)
  end

  def not_paid(subscriptions) do
    Enum.filter(subscriptions, fn subscription -> subscription.latest_invoice_amount_paid == 0 end)
  end

  def historical_active(subscriptions, date) do
    subscriptions
    |> historical_active_filter(date)
    |> historical_trialing(date, :reject)
  end

  def historical_trialing(subscriptions, date) do
    subscriptions
    |> historical_trialing(date, :filter)
    |> non_team_members()
  end

  def historical_active_filter(subscriptions, date) do
    Enum.filter(subscriptions, fn subscription ->
      if is_nil(subscription.end_date) do
        DateTime.compare(date, subscription.start_date) in [:gt, :eq]
      else
        between?(date, subscription.start_date, subscription.end_date)
      end
    end)
  end

  def historical_trialing(subscriptions, date, type) do
    case type do
      :filter ->
        Enum.filter(subscriptions, fn subscription ->
          not is_nil(subscription.trial_start) and not is_nil(subscription.trial_end) and
            between?(date, subscription.trial_start, subscription.trial_end)
        end)

      :reject ->
        Enum.reject(subscriptions, fn subscription ->
          not is_nil(subscription.trial_start) and not is_nil(subscription.trial_end) and
            between?(date, subscription.trial_start, subscription.trial_end)
        end)
    end
  end
end
