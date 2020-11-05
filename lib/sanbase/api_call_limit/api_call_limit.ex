defmodule Sanbase.ApiCallLimit do
  use Ecto.Schema

  import Ecto.{Query, Changeset}

  alias Sanbase.Repo
  alias Sanbase.Auth.User
  alias Sanbase.Billing.{Product, Subscription}

  @compile :inline_list_funcs
  @compile inline: [by_user: 1, by_remote_ip: 1]

  @default_limit 1000

  @limit_per_month_per_plan %{
    "sanbase_pro" => 5000,
    "sanapi_free" => @default_limit,
    "sanapi_basic" => 300_000,
    "sanapi_pro" => 600_000,
    "sanapi_enterprise" => :infinity,
    "sanapi_custom" => :infinity
  }

  @limit_per_hour_per_plan %{
    "sanbase_pro" => 1000,
    "sanapi_free" => 500,
    "sanapi_basic" => 3000,
    "sanapi_pro" => 6000,
    "sanapi_enterprise" => :infinity,
    "sanapi_custom" => :infinity
  }

  @quota_size 100
  def quota_size(), do: @quota_size

  @product_api_id Product.product_api()
  @product_sanbase_id Product.product_sanbase()

  schema "api_call_limits" do
    field(:has_limits, :boolean, default: true)
    field(:api_calls_limit_plan, :string, default: "free")
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
        acl
        |> changeset(%{api_calls_limit_plan: user_to_plan(user)})
        |> Repo.update()
    end
  end

  defdelegate get_quota(type, entity, auth_method), to: __MODULE__.ETS
  defdelegate update_usage(type, entity, count, auth_method), to: __MODULE__.ETS

  def get_quota_db(:user, %User{is_superuser: true}), do: {:ok, :infinity}

  def get_quota_db(type, entity) do
    case get_by(type, entity) do
      nil -> {:ok, @quota_size}
      %{has_limits: false} -> {:ok, :infinity}
      %__MODULE__{} = acl -> do_get_quota(acl)
    end
  end

  def update_usage_db(:user, %User{is_superuser: true}, _), do: :ok

  def update_usage_db(:user, %User{} = user, api_calls_count) do
    keys = get_map_keys()

    case by_user(user) do
      nil ->
        %{month_str: month_str, hour_str: hour_str} = keys

        changeset(%__MODULE__{}, %{
          user_id: user.id,
          api_calls_limit_plan: user_to_plan(user),
          has_limits: user_has_limits?(user),
          api_calls: %{month_str => api_calls_count, hour_str => api_calls_count}
        })
        |> Repo.insert()

        :ok

      %__MODULE__{} = acl ->
        do_update_usage_db(acl, api_calls_count, keys)

        :ok
    end
  end

  def update_usage_db(:remote_ip, remote_ip, api_calls_count) do
    keys = get_map_keys()

    case by_remote_ip(remote_ip) do
      nil ->
        %{month_str: month_str, hour_str: hour_str} = keys

        changeset(%__MODULE__{}, %{
          remote_ip: remote_ip,
          api_calls_limit_plan: "free",
          has_limits: remote_ip_has_limits?(remote_ip),
          api_calls: %{month_str => api_calls_count, hour_str => api_calls_count}
        })
        |> Repo.insert()

        :ok

      %__MODULE__{} = acl ->
        do_update_usage_db(acl, api_calls_count, keys)
        :ok
    end
  end

  # Private functions

  defp get_by(:user, user), do: by_user(user)
  defp get_by(:remote_ip, remote_ip), do: by_remote_ip(remote_ip)

  defp by_user(%User{} = user), do: Repo.get_by(__MODULE__, user_id: user.id)
  defp by_remote_ip(remote_ip), do: Repo.get_by(__MODULE__, remote_ip: remote_ip)

  defp get_map_keys() do
    now = Timex.now()

    %{
      month_str: now |> Timex.beginning_of_month() |> to_string(),
      hour_str: %{now | :minute => 0, :second => 0, :microsecond => {0, 0}} |> to_string()
    }
  end

  defp user_to_plan(%User{} = user) do
    api_subscription = Subscription.current_subscription(user, @product_api_id)

    case api_subscription do
      %Subscription{} ->
        plan = api_subscription |> Subscription.plan_name()
        "sanapi_#{plan}"

      _ ->
        sanbase_subscription = Subscription.current_subscription(user, @product_sanbase_id)

        case sanbase_subscription do
          %Subscription{} -> "sanbase_pro"
          _ -> "sanapi_free"
        end
    end
  end

  defp do_get_quota(%__MODULE__{} = acl) do
    %{api_calls_limit_plan: plan, api_calls: api_calls} = acl

    keys = get_map_keys()

    api_calls_this_month = Map.get(api_calls, keys.month_str, 0)
    api_calls_this_hour = Map.get(api_calls, keys.hour_str, 0)

    limit_per_month = Map.get(@limit_per_month_per_plan, plan)
    limit_per_hour = Map.get(@limit_per_hour_per_plan, plan)

    api_calls_left_this_month = Enum.max([limit_per_month - api_calls_this_month, 0])
    api_calls_left_this_hour = Enum.max([limit_per_hour - api_calls_this_hour, 0])
    api_calls_left = Enum.min([api_calls_left_this_month, api_calls_left_this_hour])

    quota = Enum.min([@quota_size, api_calls_left])

    {:ok, quota}
  end

  defp do_update_usage_db(%__MODULE__{api_calls: api_calls} = acl, count, keys) do
    %{month_str: month_str, hour_str: hour_str} = keys

    new_api_calls = %{
      month_str => count + Map.get(api_calls, month_str, 0),
      hour_str => count + Map.get(api_calls, hour_str, 0)
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
