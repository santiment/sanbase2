defmodule Sanbase.ApiCallLimit do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Accounts.User
  alias Sanbase.Billing.{Product, Subscription}

  require Logger

  @quota_size_base Application.compile_env(:sanbase, [__MODULE__, :quota_size])
  @quota_size_max_offset Application.compile_env(:sanbase, [__MODULE__, :quota_size_max_offset])
  @compile inline: [by_user: 1, by_remote_ip: 1]

  @plans_without_limits ["sanapi_enterprise", "sanapi_premium", "sanapi_custom"]
  @limits_per_month %{
    "sanbase_pro" => 5000,
    "sanapi_free" => 1000,
    "sanapi_basic" => 300_000,
    "sanapi_pro" => 600_000
  }

  @limits_per_hour %{
    "sanbase_pro" => 1000,
    "sanapi_free" => 500,
    "sanapi_basic" => 20_000,
    "sanapi_pro" => 30_000
  }

  @limits_per_minute %{
    "sanbase_pro" => 100,
    "sanapi_free" => 100,
    "sanapi_basic" => 300,
    "sanapi_pro" => 600
  }

  @product_api_id Product.product_api()
  @product_sanbase_id Product.product_sanbase()

  schema "api_call_limits" do
    field(:has_limits, :boolean, default: true)
    field(:api_calls_limit_plan, :string, default: "sanapi_free")
    field(:api_calls, :map, default: %{})
    field(:remote_ip, :string, default: nil)

    belongs_to(:user, User)
  end

  def changeset(%__MODULE__{} = acl, attrs \\ %{}) do
    acl
    |> cast(attrs, [:user_id, :remote_ip, :has_limits, :api_calls_limit_plan, :api_calls])
    |> validate_required([:has_limits, :api_calls_limit_plan])
  end

  def update_user_plan(%User{} = user) do
    case by_user(user) do
      nil ->
        {:ok, nil}

      %__MODULE__{} = acl ->
        changeset =
          acl
          |> changeset(%{api_calls_limit_plan: user_to_plan(user)})

        case Repo.update(changeset) do
          {:ok, _} = result ->
            # Clear the in-memory data for a user so the new restrictions
            # can be picked up faster. Do this only if the plan actually changes
            if new_plan = Ecto.Changeset.get_change(changeset, :api_calls_limit_plan) do
              Logger.info(
                "Updating ApiCallLimit record for user with id #{user.id}. Was: #{acl.api_calls_limit_plan}, now: #{new_plan}"
              )

              __MODULE__.ETS.clear_data(:user, user)
            end

            result

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defdelegate get_quota(type, entity, auth_method), to: __MODULE__.ETS
  defdelegate update_usage(type, entity, count, auth_method), to: __MODULE__.ETS

  def get_quota_db(type, entity) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_acl, fn _repo, _changes ->
      # {:ok, nil} | {:ok, %__MODULE__{}}
      {:ok, get_by(type, entity)}
    end)
    |> Ecto.Multi.run(:create_acl, fn _repo, %{get_acl: acl} ->
      case acl do
        nil ->
          {:ok, %__MODULE__{} = acl} = create(type, entity)
          {:ok, acl}

        %__MODULE__{} = acl ->
          {:ok, acl}
      end
    end)
    |> Ecto.Multi.run(:get_quota, fn _repo, %{create_acl: acl} ->
      do_get_quota(acl)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{get_quota: quota}} -> {:ok, quota}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  def update_usage_db(type, entity, count) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:get_acl, fn _repo, _changes ->
      # {:ok, nil} | {:ok, %__MODULE__{}}
      {:ok, get_by(type, entity)}
    end)
    |> Ecto.Multi.run(:create_acl, fn _repo, %{get_acl: acl} ->
      case acl do
        nil ->
          {:ok, %__MODULE__{} = acl} = create(type, entity)
          {:ok, acl}

        %__MODULE__{} = acl ->
          {:ok, acl}
      end
    end)
    |> Ecto.Multi.run(:update_quota, fn _repo, %{create_acl: acl} ->
      do_update_usage_db(acl, count)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{update_quota: quota}} -> {:ok, quota}
      {:error, _name, error, _} -> {:error, error}
    end
  end

  # Private functions

  defp create(type, entity, count \\ 0)

  defp create(:user, %User{} = user, count) do
    %{month_str: month_str, hour_str: hour_str, minute_str: minute_str} = get_time_str_keys()

    api_calls = %{month_str => count, hour_str => count, minute_str => count}

    plan = user_to_plan(user)

    has_limits =
      user_has_limits?(user) and
        plan not in @plans_without_limits

    %__MODULE__{}
    |> changeset(%{
      user_id: user.id,
      api_calls_limit_plan: plan,
      has_limits: has_limits,
      api_calls: api_calls
    })
    |> Repo.insert()
  end

  defp create(:remote_ip, remote_ip, count) do
    %{month_str: month_str, hour_str: hour_str, minute_str: minute_str} = get_time_str_keys()
    api_calls = %{month_str => count, hour_str => count, minute_str => count}

    %__MODULE__{}
    |> changeset(%{
      remote_ip: remote_ip,
      api_calls_limit_plan: "sanapi_free",
      has_limits: remote_ip_has_limits?(remote_ip),
      api_calls: api_calls
    })
    |> Repo.insert()
  end

  defp get_by(:user, user), do: by_user(user)
  defp get_by(:remote_ip, remote_ip), do: by_remote_ip(remote_ip)

  defp by_user(%User{} = user), do: Repo.get_by(__MODULE__, user_id: user.id)
  defp by_remote_ip(remote_ip), do: Repo.get_by(__MODULE__, remote_ip: remote_ip)

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
      %Subscription{plan: %{product: %{id: @product_api_id}}} ->
        "sanapi_#{Subscription.plan_name(subscription)}"

      %Subscription{plan: %{product: %{id: @product_sanbase_id}}} ->
        "sanbase_pro"

      _ ->
        "sanapi_free"
    end
  end

  defp do_get_quota(%__MODULE__{has_limits: false}) do
    {:ok, %{quota: :infinity}}
  end

  defp do_get_quota(%__MODULE__{} = acl) do
    %{api_calls_limit_plan: plan, api_calls: api_calls} = acl

    keys = get_time_str_keys()

    api_calls_limits = %{
      month: @limits_per_month[plan],
      hour: @limits_per_hour[plan],
      minute: @limits_per_minute[plan]
    }

    api_calls = %{
      month: Map.get(api_calls, keys.month_str, 0),
      hour: Map.get(api_calls, keys.hour_str, 0),
      minute: Map.get(api_calls, keys.minute_str, 0)
    }

    api_calls_remaining = %{
      month: Enum.max([api_calls_limits.month - api_calls.month, 0]),
      hour: Enum.max([api_calls_limits.hour - api_calls.hour, 0]),
      minute: Enum.max([api_calls_limits.minute - api_calls.minute, 0])
    }

    min_remaining = api_calls_remaining |> Map.values() |> Enum.min()
    quota_size = @quota_size_base + :rand.uniform(@quota_size_max_offset)

    case Enum.min([quota_size, min_remaining]) do
      0 ->
        now = DateTime.utc_now()

        blocked_for_seconds =
          cond do
            api_calls_remaining.month == 0 -> Timex.diff(Timex.end_of_month(now), now, :seconds)
            api_calls_remaining.hour == 0 -> 3600 - (now.minute * 60 + now.second)
            api_calls_remaining.minute == 0 -> 60 - now.second
          end

        {:error,
         %{
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
           api_calls_limits: api_calls_limits
         }}
    end
  end

  defp do_update_usage_db(%__MODULE__{api_calls: api_calls} = acl, count) do
    %{month_str: month_str, hour_str: hour_str, minute_str: minute_str} = get_time_str_keys()

    new_api_calls = %{
      month_str => count + Map.get(api_calls, month_str, 0),
      hour_str => count + Map.get(api_calls, hour_str, 0),
      minute_str => count + Map.get(api_calls, minute_str, 0)
    }

    changeset(acl, %{api_calls: new_api_calls})
    |> Repo.update()
  end

  defp user_has_limits?(%User{is_superuser: true}), do: false

  defp user_has_limits?(%User{email: email}) when is_binary(email),
    do: not String.ends_with?(email, "@santiment.net")

  defp user_has_limits?(%User{}), do: true

  defp remote_ip_has_limits?(remote_ip) do
    not (Sanbase.Utils.IP.is_san_cluster_ip?(remote_ip) or
           Sanbase.Utils.IP.is_localhost?(remote_ip))
  end
end
