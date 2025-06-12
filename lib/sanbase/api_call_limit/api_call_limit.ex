defmodule Sanbase.ApiCallLimit do
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.Product
  alias Sanbase.Billing.Subscription
  alias Sanbase.ApiCallLimit.Restrictions

  require Logger

  @quota_size_base Application.compile_env(:sanbase, [__MODULE__, :quota_size])
  @quota_size_max_offset Application.compile_env(:sanbase, [__MODULE__, :quota_size_max_offset])

  # So we can use them in pattern matching in case
  @product_api_id Product.product_api()
  @product_sanbase_id Product.product_sanbase()

  @plans_without_limits [
    "sanapi_enterprise",
    "sanapi_custom"
  ]
  @api_call_limits_per_month Restrictions.call_limits_per_month()
  @api_call_limits_per_hour Restrictions.call_limits_per_hour()
  @api_call_limits_per_minute Restrictions.call_limits_per_minute()

  @response_size_limits_mb_per_month Restrictions.response_size_limits_mb_per_month()
  # @response_size_limits_per_hour Restrictions.response_size_limits_per_hour()
  # @response_size_limits_per_minute Restrictions.response_size_limits_per_minute()

  schema "api_call_limits" do
    # If has_limits_no_matter_plan is false then plan is not checked.
    # This is used for manually setting no limits api customers without resetting on plan change.
    field(:has_limits_no_matter_plan, :boolean, default: true)
    field(:has_limits, :boolean, default: true)
    field(:api_calls_limit_plan, :string, default: "sanapi_free")
    field(:api_calls_limit_subscription_status, :string, default: "active")
    field(:api_calls, :map, default: %{})
    field(:api_calls_responses_size_mb, :map, default: %{})
    field(:remote_ip, :string, default: nil)

    belongs_to(:user, User)
  end

  def changeset(%__MODULE__{} = acl, attrs \\ %{}) do
    acl
    |> cast(attrs, [
      :user_id,
      :remote_ip,
      :has_limits_no_matter_plan,
      :has_limits,
      :api_calls_limit_plan,
      :api_calls_limit_subscription_status,
      :api_calls,
      :api_calls_responses_size_mb
    ])
    |> validate_required([:has_limits, :api_calls_limit_plan])
  end

  def update_user_plan(%User{} = user) do
    %__MODULE__{} = acl = get_by_and_lock(:user, user)

    {plan, subscription_status} = user_to_plan(user)

    # Some users have don't have limits regardless of their plan
    # In case the user has limits - check the plan
    has_limits =
      case user_has_limits?(user) do
        false -> false
        true -> plan_has_limits?(plan)
      end

    changeset =
      acl
      |> changeset(%{
        api_calls_limit_plan: plan,
        api_calls_limit_subscription_status: subscription_status,
        has_limits: has_limits
      })

    case Repo.update(changeset) do
      {:ok, _} = result ->
        # Clear the in-memory data for a user so the new restrictions
        # can be picked up faster. Do this only if the plan actually changes
        __MODULE__.ETS.clear_data(:user, user)

        if new_plan = Ecto.Changeset.get_change(changeset, :api_calls_limit_plan) do
          Logger.info(
            "Updating ApiCallLimit record for user with id #{user.id}. Was: #{acl.api_calls_limit_plan}, now: #{new_plan}"
          )
        end

        result

      {:error, error} ->
        {:error, error}
    end
  end

  defdelegate get_quota(type, entity, auth_method), to: __MODULE__.ETS
  defdelegate update_usage(type, entity, count, auth_method, result_byte_size), to: __MODULE__.ETS

  def get_quota_db(type, entity) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_acl, fn _repo, _changes ->
      {:ok, get_by(type, entity)}
    end)
    |> Ecto.Multi.run(:get_quota, fn _repo, %{get_acl: acl} ->
      do_get_quota(acl)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{get_quota: quota}} -> {:ok, quota}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  def update_usage_db(type, entity, count, result_byte_size) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_acl, fn _repo, _changes ->
      {:ok, get_by_and_lock(type, entity)}
    end)
    |> Ecto.Multi.run(:update_quota, fn _repo, %{get_acl: acl} ->
      do_update_usage_db(acl, count, result_byte_size)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update_quota: quota}} -> {:ok, quota}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  def reset(%User{} = user) do
    if struct = Repo.get_by(__MODULE__, user_id: user.id), do: Repo.delete!(struct)

    case create(:user, user) do
      {:ok, acl} -> {:ok, acl}
      {:error, _} -> {:error, "Failed to reset the API call limits of user #{user.id}"}
    end
  end

  # Private functions

  defp create(type, entity)

  defp create(:user, %User{} = user) do
    %{month_str: month_str, hour_str: hour_str, minute_str: minute_str} = get_time_str_keys()

    api_calls = %{month_str => 0, hour_str => 0, minute_str => 0}
    response_sizes = %{month_str => 0, hour_str => 0, minute_str => 0}
    {subscription_plan, subscription_status} = user_to_plan(user)

    has_limits =
      user_has_limits?(user) and
        subscription_plan not in @plans_without_limits

    %__MODULE__{}
    |> changeset(%{
      user_id: user.id,
      api_calls_limit_plan: subscription_plan,
      api_calls_limit_subscription_status: subscription_status,
      has_limits: has_limits,
      api_calls: api_calls,
      api_calls_responses_size_mb: response_sizes
    })
    |> Repo.insert()
  end

  defp create(:remote_ip, remote_ip) do
    %{month_str: month_str, hour_str: hour_str, minute_str: minute_str} = get_time_str_keys()

    api_calls = %{month_str => 0, hour_str => 0, minute_str => 0}
    response_sizes = %{month_str => 0, hour_str => 0, minute_str => 0}

    %__MODULE__{}
    |> changeset(%{
      remote_ip: remote_ip,
      api_calls_limit_plan: "sanapi_free",
      api_calls_limit_subscription_status: "active",
      has_limits: remote_ip_has_limits?(remote_ip),
      api_calls: api_calls,
      api_calls_responses_size_mb: response_sizes
    })
    |> Repo.insert()
  end

  defp get_by(:user, user) do
    case Repo.get_by(__MODULE__, user_id: user.id) do
      nil ->
        {:ok, acl} = create(:user, user)
        acl

      %__MODULE__{} = acl ->
        acl
    end
  end

  defp get_by(:remote_ip, remote_ip) do
    case Repo.get_by(__MODULE__, remote_ip: remote_ip) do
      nil ->
        {:ok, acl} = create(:remote_ip, remote_ip)
        acl

      %__MODULE__{} = acl ->
        acl
    end
  end

  defp get_by_and_lock(:user, user) do
    result =
      from(acl in __MODULE__,
        where: acl.user_id == ^user.id,
        lock: "FOR UPDATE"
      )
      |> Repo.one()

    case result do
      nil ->
        # Ensure that the result we get back has a lock. This is making more
        # DB calls, but it should be executed only once per user/remote_ip and
        # after that all subsequent calls should go into the second case.
        {:ok, _acl} = create(:user, user)
        get_by_and_lock(:user, user)

      %__MODULE__{} = acl ->
        acl
    end
  end

  defp get_by_and_lock(:remote_ip, remote_ip) do
    from(acl in __MODULE__,
      where: acl.remote_ip == ^remote_ip,
      lock: "FOR UPDATE"
    )
    |> Repo.one()
    |> case do
      nil ->
        # Ensure that the result we get back has a lock. This is making more
        # DB calls, but it should be executed only once per user/remote_ip and
        # after that all subsequent calls should go into the second case.
        {:ok, _acl} = create(:remote_ip, remote_ip)
        get_by_and_lock(:remote_ip, remote_ip)

      %__MODULE__{} = acl ->
        acl
    end
  end

  defp get_time_str_keys() do
    now = DateTime.utc_now()

    %{
      month_str: now |> Timex.beginning_of_month() |> to_string(),
      hour_str: %{now | :minute => 0, :second => 0, :microsecond => {0, 0}} |> to_string(),
      minute_str: %{now | :second => 0, :microsecond => {0, 0}} |> to_string()
    }
  end

  defp user_to_plan(%User{} = user) do
    subscription =
      Subscription.current_subscription(user, @product_api_id) ||
        Subscription.current_subscription(user, @product_sanbase_id)

    case subscription do
      %Subscription{status: status, plan: %{product: %{id: @product_api_id}}} ->
        {"sanapi_#{Subscription.plan_name(subscription)}" |> String.downcase(), to_string(status)}

      %Subscription{status: status, plan: %{product: %{id: @product_sanbase_id}}} ->
        {"sanbase_#{Subscription.plan_name(subscription)}" |> String.downcase(),
         to_string(status)}

      _ ->
        {"sanapi_free", "active"}
    end
  end

  defp do_get_quota(%__MODULE__{has_limits_no_matter_plan: false}) do
    {:ok, %{quota: :infinity}}
  end

  defp do_get_quota(%__MODULE__{has_limits: false}) do
    {:ok, %{quota: :infinity}}
  end

  defp do_get_quota(%__MODULE__{} = acl) do
    # The api calls made in the specified period

    with :ok <- check_result_size_limits(acl),
         {:ok, %{} = map} <- check_api_calls_limits(acl) do
      {:ok, map}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp check_result_size_limits(
         %__MODULE__{api_calls_limit_subscription_status: status, api_calls_limit_plan: plan} =
           acl
       )
       when status in ["trialing"] or plan == "sanapi_free" do
    %{api_calls_responses_size_mb: api_calls_responses_size_mb, api_calls_limit_plan: plan} = acl
    %{month_str: month_str} = get_time_str_keys()

    size_limits = plan_to_response_size_limits(plan)
    now = DateTime.utc_now()

    cond do
      (api_calls_responses_size_mb[month_str] || 0) > size_limits.month ->
        blocked_for_seconds = DateTime.diff(Timex.end_of_month(now), now, :second)

        {:error,
         %{
           reason: :response_size_limit_exceeded,
           blocked_until: DateTime.add(now, blocked_for_seconds, :second),
           blocked_for_seconds: blocked_for_seconds
         }}

      # NOTE: Currently only the monthly limits are applied
      #
      # (api_calls_responses_size_mb[hour_str] || 0) > 100 ->
      #   {:error, "The API response size for the hour exceeded the limit of 100 MB."}
      #
      # (api_calls_responses_size_mb[minute_str] || 0) > 10 ->
      #   {:error, "The API response size for the minute exceeded the limit of 10 MB."}

      true ->
        :ok
    end
  end

  defp check_result_size_limits(_acl), do: :ok

  defp check_api_calls_limits(%__MODULE__{} = acl) do
    {
      %{month: _, hour: _, minute: _} = api_calls_remaining,
      %{month: _, hour: _, minute: _} = api_calls_limits
    } = get_api_calls_maps(acl)

    # The min remaining calls among the minute, hour and values
    min_remaining = api_calls_remaining |> Map.values() |> Enum.min()
    # Randomize the quota size so when the API calls are distributed among all
    # API pods the quotas don't expire at the same time
    quota_size = @quota_size_base + :rand.uniform(@quota_size_max_offset)

    case Enum.min([quota_size, min_remaining]) do
      0 ->
        now = DateTime.utc_now()

        blocked_for_seconds =
          cond do
            api_calls_remaining.month == 0 -> DateTime.diff(Timex.end_of_month(now), now, :second)
            api_calls_remaining.hour == 0 -> 3600 - (now.minute * 60 + now.second)
            api_calls_remaining.minute == 0 -> 60 - now.second
          end

        {:error,
         %{
           reason: :rate_limited,
           blocked_until: DateTime.add(now, blocked_for_seconds, :second),
           blocked_for_seconds: blocked_for_seconds,
           api_calls_remaining: api_calls_remaining,
           api_calls_limits: api_calls_limits
         }}

      quota ->
        {:ok,
         %{
           quota: quota,
           api_calls_remaining: api_calls_remaining,
           api_calls_limits: api_calls_limits,
           api_calls_responses_size_mb: get_response_sizes_in_mb_map(acl)
         }}
    end
  end

  defp get_api_calls_maps(%__MODULE__{api_calls_limit_plan: plan, api_calls: api_calls_made}) do
    keys = get_time_str_keys()

    api_calls_limits = plan_to_api_call_limits(plan)

    api_calls_made = %{
      month: Map.get(api_calls_made, keys.month_str, 0),
      hour: Map.get(api_calls_made, keys.hour_str, 0),
      minute: Map.get(api_calls_made, keys.minute_str, 0)
    }

    api_calls_remaining = %{
      month: Enum.max([api_calls_limits.month - api_calls_made.month, 0]),
      hour: Enum.max([api_calls_limits.hour - api_calls_made.hour, 0]),
      minute: Enum.max([api_calls_limits.minute - api_calls_made.minute, 0])
    }

    {api_calls_remaining, api_calls_limits}
  end

  defp get_response_sizes_in_mb_map(%__MODULE__{
         api_calls_responses_size_mb: api_calls_responses_size_mb
       }) do
    keys = get_time_str_keys()

    %{
      month: Map.get(api_calls_responses_size_mb, keys.month_str, 0),
      hour: Map.get(api_calls_responses_size_mb, keys.hour_str, 0),
      minute: Map.get(api_calls_responses_size_mb, keys.minute_str, 0)
    }
  end

  defp do_update_usage_db(%__MODULE__{} = acl, count, acc_results_byte_size)
       when is_integer(count) and is_integer(acc_results_byte_size) do
    %{month_str: month_str, hour_str: hour_str, minute_str: minute_str} = get_time_str_keys()
    %{api_calls: api_calls, api_calls_responses_size_mb: api_calls_responses_size_mb} = acl

    new_api_calls = %{
      month_str => count + Map.get(api_calls, month_str, 0),
      hour_str => count + Map.get(api_calls, hour_str, 0),
      minute_str => count + Map.get(api_calls, minute_str, 0)
    }

    # Store in mb instead of bytes so the value reached by accumulating results for
    # a whole month is easier to work with
    result_mb = acc_results_byte_size |> Kernel./(1024 * 1024) |> Float.round(6)

    new_api_responses_size_mb = %{
      month_str => result_mb + Map.get(api_calls_responses_size_mb, month_str, 0),
      hour_str => result_mb + Map.get(api_calls_responses_size_mb, hour_str, 0),
      minute_str => result_mb + Map.get(api_calls_responses_size_mb, minute_str, 0)
    }

    changeset(acl, %{
      api_calls: new_api_calls,
      api_calls_responses_size_mb: new_api_responses_size_mb
    })
    |> Repo.update()
  end

  defp plan_has_limits?(plan) do
    case plan do
      plan when plan in @plans_without_limits ->
        false

      "sanapi_custom_" <> _ ->
        [product_code, plan_name] = plan |> String.upcase() |> String.split("_", parts: 2)

        case Sanbase.Billing.Plan.CustomPlan.Access.api_call_limits(plan_name, product_code) do
          %{"has_limits" => false} -> false
          _ -> true
        end

      _ ->
        true
    end
  end

  defp user_has_limits?(%User{is_superuser: true}), do: false

  defp user_has_limits?(%User{email: email}) when is_binary(email),
    do: not String.ends_with?(email, "@santiment.net")

  defp user_has_limits?(%User{}), do: true

  defp remote_ip_has_limits?(remote_ip) do
    not (Sanbase.Utils.IP.san_cluster_ip?(remote_ip) or
           Sanbase.Utils.IP.localhost?(remote_ip))
  end

  defp plan_to_api_call_limits(plan) do
    case plan do
      "sanapi_custom_" <> _ ->
        "sanapi_" <> plan_name = plan
        plan_name = String.upcase(plan_name)

        %{"month" => month, "hour" => hour, "minute" => minute} =
          Sanbase.Billing.Plan.CustomPlan.Access.api_call_limits(plan_name, "SANAPI")

        %{month: month, hour: hour, minute: minute}

      _ ->
        %{
          month: @api_call_limits_per_month[plan],
          hour: @api_call_limits_per_hour[plan],
          minute: @api_call_limits_per_minute[plan]
        }
    end
  end

  defp plan_to_response_size_limits(plan) do
    case plan do
      "sanapi_custom_" <> _ ->
        "sanapi_" <> plan_name = plan
        plan_name = String.upcase(plan_name)

        %{"month" => month} =
          Sanbase.Billing.Plan.CustomPlan.Access.response_size_limits(plan_name, "SANAPI")

        # Not using hour/minute limits for now
        %{month: month}

      _ ->
        %{
          month: @response_size_limits_mb_per_month[plan]
        }
    end
  end
end
