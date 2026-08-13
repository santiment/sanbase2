defmodule Sanbase.Billing.Subscription.PromoTrial do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Billing
  alias Sanbase.StripeApi
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Subscription, Plan, Product}

  import Ecto.Query

  require Logger

  schema "promo_trials" do
    field(:trial_days, :integer)
    field(:plans, {:array, :string})
    # The subscriptions created by this promo trial. Empty for records created
    # before the column existed - those fall back to matching by user and
    # creation time, see with_subscriptions/1.
    field(:subscription_ids, {:array, :integer}, default: [])
    belongs_to(:user, User)

    timestamps()
  end

  def changeset(%__MODULE__{} = promo_trial, attrs \\ %{}) do
    promo_trial
    |> cast(attrs, [
      :user_id,
      :trial_days,
      :plans,
      :subscription_ids
    ])
    |> stringify_plans(attrs)
  end

  @doc """
  Return a map of plan_id (as string) => "Product Name / Plan Name" for all
  non-deprecated plans in the database.
  """
  def plan_id_name_map do
    Map.new(plan_id_name_list(), fn {name, id} -> {id, name} end)
  end

  @doc """
  Return an ordered list of {name, id} tuples for all eligible promo trial plans,
  grouped by product (SanAPI first, then Sanbase).
  """
  def plan_id_name_list do
    promo_trial_plans_query()
    |> select([p, prod], {p.id, prod.name, p.name, p.interval})
    |> Sanbase.Repo.all()
    |> Enum.map(fn {id, product_name, plan_name, interval} ->
      {"#{product_name} / #{plan_name} (#{interval})", Integer.to_string(id)}
    end)
  end

  @doc """
  Return a list of all non-deprecated, non-free plan IDs
  for products that support promo trials (SANAPI and Sanbase).
  """
  def promo_trial_plans do
    promo_trial_plans_query()
    |> select([p], p.id)
    |> Sanbase.Repo.all()
  end

  @doc """
  Return promo-trial-eligible plans grouped by product and interval.

  Shape: %{api: %{"month" => [%{id, name, stripe_id}, ...], "year" => [...]},
           sanbase: %{"month" => [...], "year" => [...]}}
  """
  def plans_grouped do
    promo_trial_plans_query()
    |> select([p, prod], %{
      id: p.id,
      name: p.name,
      interval: p.interval,
      product_id: prod.id,
      stripe_id: p.stripe_id
    })
    |> Sanbase.Repo.all()
    |> Enum.group_by(
      fn p ->
        cond do
          p.product_id == Product.product_api() -> :api
          p.product_id == Product.product_sanbase() -> :sanbase
        end
      end,
      fn p -> %{id: p.id, name: p.name, interval: p.interval, stripe_id: p.stripe_id} end
    )
    |> Map.new(fn {product_key, plans} ->
      {product_key, Enum.group_by(plans, & &1.interval)}
    end)
  end

  defp promo_trial_plans_query do
    from(p in Plan,
      join: prod in assoc(p, :product),
      where: not p.is_deprecated,
      where: p.name != "FREE",
      where: prod.id in ^[Product.product_api(), Product.product_sanbase()],
      order_by: [asc: prod.id, asc: p.id]
    )
  end

  def create_promo_trial(%{"plans" => plans, "trial_days" => trial_days, "user_id" => user_id}) do
    create_promo_trial(%{plans: plans, trial_days: trial_days, user_id: user_id})
  end

  def create_promo_trial(%{plans: plans, trial_days: trial_days, user_id: user_id})
      when is_list(plans) do
    user_id = maybe_convert_to_integer(user_id)
    {:ok, user} = User.by_id(user_id)
    plans = Enum.map(plans, &maybe_convert_to_integer/1)
    trial_days = maybe_convert_to_integer(trial_days)

    create_promo_subscriptions(user, plans, trial_days)
  end

  def create_promo_trial(%{plan_id: plan_id, trial_days: trial_days, user_id: user_id}) do
    plan_id = maybe_convert_to_integer(plan_id)
    {:ok, user} = User.by_id(user_id)
    trial_days = maybe_convert_to_integer(trial_days)

    create_promo_subscription(user, plan_id, trial_days)
  end

  defp create_promo_subscriptions(%User{} = user, plans, trial_days) when is_list(plans) do
    with {:ok, user} <- Billing.create_or_update_stripe_customer(user),
         {:ok, subscriptions} <- promo_subscribe(user, plans, trial_days),
         {:ok, _promo_trial} <-
           insert_promo_trial_record(user.id, plans, trial_days, subscriptions) do
      {:ok, subscriptions}
    else
      {:error, error} ->
        handle_error(user, error)
    end
  end

  defp create_promo_subscription(%User{} = user, plan_id, trial_days) do
    with {:ok, user} <- Billing.create_or_update_stripe_customer(user),
         {:ok, subscription} <- promo_subscribe(user, plan_id, trial_days),
         {:ok, _promo_trial} <-
           insert_promo_trial_record(user.id, [plan_id], trial_days, [subscription]) do
      {:ok, subscription}
    else
      {:error, error} ->
        handle_error(user, error)
    end
  end

  defp insert_promo_trial_record(user_id, plans, trial_days, subscriptions) do
    plan_ids = Enum.map(plans, &to_string/1)
    subscription_ids = subscriptions |> List.wrap() |> Enum.map(& &1.id)

    %__MODULE__{}
    |> changeset(%{
      user_id: user_id,
      trial_days: trial_days,
      plans: plan_ids,
      subscription_ids: subscription_ids
    })
    |> Sanbase.Repo.insert()
  end

  defp promo_subscribe(user, plan_ids, trial_days) when is_list(plan_ids) do
    subscriptions =
      Plan.by_ids(plan_ids)
      |> Enum.map(&subscribe_to_plan(user, &1, trial_days))

    groups = Enum.group_by(subscriptions, fn {ok_or_error, _} -> ok_or_error end)

    if errors = Map.get(groups, :error) do
      hd(errors)
    else
      {:ok, Map.get(groups, :ok, []) |> Enum.map(&elem(&1, 1))}
    end
  end

  defp promo_subscribe(user, plan_id, trial_days) do
    plan = Plan.by_id(plan_id)

    subscribe_to_plan(user, plan, trial_days)
  end

  defp subscribe_to_plan(user, plan, trial_days) do
    subscription_data = promotional_subsciption_data(user, plan, trial_days)

    with {:ok, stripe_sub} <- StripeApi.create_subscription(subscription_data),
         {:ok, subscription} <- Subscription.create_subscription_db(stripe_sub, user, plan) do
      {:ok, subscription}
    end
  end

  defp promotional_subsciption_data(user, plan, trial_days) do
    trial_end_unix = Timex.shift(Timex.now(), days: trial_days) |> DateTime.to_unix()

    %{
      customer: user.stripe_customer_id,
      items: [%{plan: plan.stripe_id}],
      trial_end: trial_end_unix,
      cancel_at: trial_end_unix - 60
    }
  end

  # ---------------------------------------------------------------------------
  # Managing already granted promo trials
  # ---------------------------------------------------------------------------

  @doc """
  A page of promo trials, newest first, each paired with the subscriptions it created.

  Returns `{rows, total_count}` where every row is
  `%{promo_trial: %PromoTrial{}, subscriptions: [%Subscription{}]}`.

  Options: `:page` (1-based), `:page_size`, `:search` (user email, username or id).
  """
  def list_with_subscriptions(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)

    query = opts |> Keyword.get(:search) |> search_query()
    total = Sanbase.Repo.aggregate(query, :count, :id)

    promo_trials =
      query
      |> order_by([pt], desc: pt.id)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))
      |> preload(:user)
      |> Sanbase.Repo.all()

    {with_subscriptions(promo_trials), total}
  end

  @doc """
  Pair every promo trial with the subscriptions it created.

  Records granted before `subscription_ids` was stored keep no link to their
  subscriptions, so for those the user's subscriptions created around the same
  time as the promo trial record are used instead.
  """
  def with_subscriptions(promo_trials) when is_list(promo_trials) do
    linked_ids = promo_trials |> Enum.flat_map(& &1.subscription_ids) |> Enum.uniq()

    unlinked_user_ids =
      promo_trials
      |> Enum.filter(&(&1.subscription_ids == []))
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()

    subscriptions =
      from(s in Subscription,
        where: s.id in ^linked_ids or s.user_id in ^unlinked_user_ids,
        preload: [plan: :product]
      )
      |> Sanbase.Repo.all()

    by_id = Map.new(subscriptions, &{&1.id, &1})
    by_user_id = Enum.group_by(subscriptions, & &1.user_id)

    Enum.map(promo_trials, fn promo_trial ->
      subscriptions =
        case promo_trial.subscription_ids do
          [] ->
            by_user_id
            |> Map.get(promo_trial.user_id, [])
            |> legacy_subscriptions(promo_trial)

          ids ->
            ids |> Enum.map(&Map.get(by_id, &1)) |> Enum.reject(&is_nil/1)
        end

      %{promo_trial: promo_trial, subscriptions: Enum.sort_by(subscriptions, & &1.id)}
    end)
  end

  @doc """
  The subscriptions created by a single promo trial.
  """
  def subscriptions(%__MODULE__{} = promo_trial) do
    [%{subscriptions: subscriptions}] = with_subscriptions([promo_trial])
    subscriptions
  end

  @doc """
  The moment a promo trial of `trial_days` days ends, counted from when it was granted.
  """
  def trial_end_for(%__MODULE__{inserted_at: inserted_at}, trial_days) do
    inserted_at
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.add(trial_days * 24 * 3600, :second)
  end

  @doc """
  Change the length of an already granted promo trial and push it to Stripe.

  `trial_days` is the total length counted from the day the trial was granted, not
  an increment - passing a smaller number than the current one shortens the trial.
  Every still trialing subscription gets both its `trial_end` and the `cancel_at`
  that ends it just before the first charge moved to the new date. The local
  promo trial record is only updated once every Stripe call has succeeded.
  """
  @spec update_trial_days(%__MODULE__{}, pos_integer()) ::
          {:ok, %__MODULE__{}} | {:error, String.t()}
  def update_trial_days(%__MODULE__{} = promo_trial, trial_days)
      when is_integer(trial_days) and trial_days > 0 do
    trial_end = trial_end_for(promo_trial, trial_days)

    case DateTime.compare(trial_end, DateTime.utc_now()) do
      :gt ->
        do_update_trial_days(promo_trial, trial_days, trial_end)

      _ ->
        {:error,
         "A #{trial_days} day trial granted on #{format_datetime(promo_trial.inserted_at)} " <>
           "would have ended on #{format_datetime(trial_end)}. Cancel the subscriptions instead."}
    end
  end

  @doc """
  Cancel a promo trial subscription in Stripe immediately and sync the local record.

  Cancelling immediately rather than at the period end is what ends a trial - a
  trialing subscription has nothing paid for that the user could use up.
  """
  @spec cancel_subscription(%Subscription{}) :: {:ok, %Subscription{}} | {:error, any()}
  def cancel_subscription(%Subscription{stripe_id: stripe_id} = subscription)
      when is_binary(stripe_id) do
    with {:ok, stripe_subscription} <- StripeApi.cancel_subscription_immediately(stripe_id, %{}),
         {:ok, db_subscription} <-
           Subscription.sync_subscription_with_stripe(stripe_subscription, subscription) do
      {:ok, db_subscription}
    end
  end

  def cancel_subscription(%Subscription{id: id}),
    do: {:error, "Subscription ##{id} has no Stripe id and cannot be cancelled."}

  @doc """
  Cancel every not yet cancelled subscription of a promo trial. Returns the number cancelled.
  """
  @spec cancel_subscriptions(%__MODULE__{}) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def cancel_subscriptions(%__MODULE__{} = promo_trial) do
    case Enum.reject(subscriptions(promo_trial), &(&1.status == :canceled)) do
      [] ->
        {:error, "All subscriptions of this promo trial are already cancelled."}

      subscriptions ->
        {cancelled, errors} =
          subscriptions
          |> Enum.map(&cancel_subscription/1)
          |> Enum.split_with(&match?({:ok, _}, &1))

        case errors do
          [] ->
            {:ok, length(cancelled)}

          errors ->
            {:error,
             "Cancelled #{length(cancelled)}/#{length(subscriptions)} subscriptions. " <>
               error_messages(errors)}
        end
    end
  end

  defp do_update_trial_days(promo_trial, trial_days, trial_end) do
    case Enum.filter(subscriptions(promo_trial), &(&1.status == :trialing)) do
      [] ->
        {:error,
         "No trialing subscriptions left - they have already been cancelled or their trials ended."}

      subscriptions ->
        {updated, errors} =
          subscriptions
          |> Enum.map(&move_trial_end(&1, trial_end))
          |> Enum.split_with(&match?({:ok, _}, &1))

        case errors do
          [] ->
            promo_trial
            |> changeset(%{trial_days: trial_days})
            |> Sanbase.Repo.update()
            |> case do
              {:ok, promo_trial} -> {:ok, promo_trial}
              {:error, changeset} -> {:error, inspect(changeset.errors)}
            end

          errors ->
            {:error,
             "Updated #{length(updated)}/#{length(subscriptions)} subscriptions in Stripe. " <>
               error_messages(errors)}
        end
    end
  end

  defp move_trial_end(%Subscription{stripe_id: stripe_id} = subscription, trial_end)
       when is_binary(stripe_id) do
    trial_end_unix = DateTime.to_unix(trial_end)

    params = %{
      trial_end: trial_end_unix,
      cancel_at: trial_end_unix - 60,
      proration_behavior: "none"
    }

    with {:ok, stripe_subscription} <- StripeApi.update_subscription(stripe_id, params),
         {:ok, db_subscription} <-
           Subscription.sync_subscription_with_stripe(stripe_subscription, subscription) do
      {:ok, db_subscription}
    end
  end

  defp move_trial_end(%Subscription{id: id}, _trial_end),
    do: {:error, "Subscription ##{id} has no Stripe id and cannot be updated."}

  # Promo subscriptions are created in Stripe seconds before the promo trial row
  # is written, so a small window around it identifies them for legacy records.
  @legacy_match_window_seconds 600

  # Records granted before subscription_ids was stored have to be matched by hand.
  # A candidate has to be a trial of the user created around the same moment; of
  # those, the ones on a plan the promo trial granted win. The plan names stored
  # on old records do not always resolve - a renamed product is enough to miss -
  # so when nothing matches by plan, the trials created alongside it are kept
  # rather than dropping the link altogether.
  defp legacy_subscriptions(user_subscriptions, %__MODULE__{} = promo_trial) do
    candidates =
      Enum.filter(user_subscriptions, fn subscription ->
        not is_nil(subscription.trial_end) and created_together?(subscription, promo_trial)
      end)

    case Enum.filter(candidates, &granted_plan?(&1, promo_trial)) do
      [] -> candidates
      matched -> matched
    end
  end

  defp created_together?(%Subscription{} = subscription, %__MODULE__{} = promo_trial) do
    abs(NaiveDateTime.diff(subscription.inserted_at, promo_trial.inserted_at)) <=
      @legacy_match_window_seconds
  end

  defp granted_plan?(%Subscription{plan_id: plan_id} = subscription, %__MODULE__{plans: plans}) do
    to_string(plan_id) in plans or plan_label(subscription.plan) in plans
  end

  defp plan_label(%Plan{name: name, interval: interval, product: %Product{name: product_name}}),
    do: "#{product_name} / #{name} (#{interval})"

  defp plan_label(_), do: nil

  defp search_query(search) when is_binary(search) and byte_size(search) > 0 do
    pattern = "%" <> String.trim(search) <> "%"

    query =
      from(pt in __MODULE__,
        join: u in assoc(pt, :user),
        where: ilike(u.email, ^pattern) or ilike(u.username, ^pattern)
      )

    case Integer.parse(String.trim(search)) do
      {id, ""} -> from([pt, u] in query, or_where: u.id == ^id or pt.id == ^id)
      _ -> query
    end
  end

  defp search_query(_), do: from(pt in __MODULE__)

  defp error_messages(errors) do
    errors
    |> Enum.map(fn {:error, reason} -> error_message(reason) end)
    |> Enum.join("; ")
  end

  defp error_message(%Stripe.Error{message: message}), do: message
  defp error_message(%Ecto.Changeset{} = changeset), do: inspect(changeset.errors)
  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason), do: inspect(reason)

  defp format_datetime(%NaiveDateTime{} = naive),
    do: naive |> DateTime.from_naive!("Etc/UTC") |> format_datetime()

  defp format_datetime(%DateTime{} = datetime),
    do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M UTC")

  defp handle_error(user, error) do
    case error do
      %Stripe.Error{message: message} = error ->
        log_error(user, error)
        {:error, message}

      error_msg when is_binary(error_msg) ->
        log_error(user, error)
        {:error, error_msg}

      error ->
        log_error(user, error)
        {:error, error}
    end
  end

  defp log_error(user, error) do
    Logger.error(
      "Error creating promotional subscription for user: #{inspect(user)}, reason: #{inspect(error)}"
    )
  end

  defp stringify_plans(changeset, %{plans: plans}) do
    id_name_map = plan_id_name_map()
    put_change(changeset, :plans, Enum.map(plans, &(id_name_map[&1] || &1)))
  end

  defp stringify_plans(changeset, _), do: changeset

  defp maybe_convert_to_integer(value) when is_integer(value) do
    value
  end

  defp maybe_convert_to_integer(value) when is_binary(value) do
    String.to_integer(value)
  end
end
