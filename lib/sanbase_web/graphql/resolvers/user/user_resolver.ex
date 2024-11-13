defmodule SanbaseWeb.Graphql.Resolvers.UserResolver do
  require Logger

  import Sanbase.Utils.ErrorHandling, only: [changeset_errors: 1, changeset_errors_string: 1]
  import Absinthe.Resolution.Helpers, except: [async: 1]
  import SanbaseWeb.Graphql.Helpers.Utils, only: [requested_fields: 1]

  alias Sanbase.InternalServices.Ethauth
  alias Sanbase.Accounts.User
  alias Sanbase.Accounts.UserFollower
  alias Sanbase.Accounts.UserSettings
  alias SanbaseWeb.Graphql.SanbaseDataloader

  def is_moderator(_root, _args, %{context: %{is_moderator: is_moderator}}) do
    {:ok, is_moderator}
  end

  def is_moderator(_root, _args, _resolution), do: {:ok, false}

  def email(%User{email: nil}, _args, _resolution), do: {:ok, nil}

  def email(%User{id: id, email: email}, _args, %{
        context: %{auth: %{current_user: %User{id: id}}}
      }) do
    {:ok, email}
  end

  def email(%User{} = user, _args, _resolution) do
    {:ok, User.Public.hide_private_data(user).email}
  end

  def permissions(
        %User{} = user,
        _args,
        _resolution
      ) do
    {:ok, User.Permissions.permissions(user)}
  end

  @spec san_balance(%User{}, map(), Absinthe.Resolution.t()) :: {:ok, float()}
  def san_balance(
        %User{} = user,
        _args,
        _res
      ) do
    case User.san_balance(user) do
      {:ok, san_balance} ->
        {:ok, san_balance || 0}

      {:error, error} ->
        Logger.warning("Error getting a user's san balance. Reason: #{inspect(error)}")
        {:nocache, {:ok, 0.0}}
    end
  end

  def api_calls_history(
        %User{} = user,
        %{from: from, to: to, interval: interval} = args,
        _resolution
      ) do
    auth_method = Map.get(args, :auth_method, :all)
    Sanbase.Clickhouse.ApiCallData.api_call_history(user.id, from, to, interval, auth_method)
  end

  def api_calls_count(
        %User{} = user,
        %{from: from, to: to} = args,
        _resolution
      ) do
    auth_method = Map.get(args, :auth_method, :all)
    Sanbase.Clickhouse.ApiCallData.api_call_count(user.id, from, to, auth_method)
  end

  def current_user(
        _root,
        _args,
        %{context: %{origin_url: origin_url, auth: %{current_user: user}}} = resolution
      ) do
    first_login_requested? = "firstLogin" in requested_fields(resolution)

    # Appart from finishing the registration process, this code will also set the
    # firstLogin: true, which is **very** important for the analytics, as the frontend
    # uses it to emit events.
    # The frontend can execute some other currentUser queries that do not request this field
    # before executing any request that does include this field.
    # In such cases these queries could actually trigger the firstLogin: true
    # and any other query that actually asks for it will see false.
    # Fix this by finishing the registration process and putting firstLogin: true
    # only when the `firstLogin` field is requested.
    case first_login_requested? and User.RegistrationState.login_to_finish_registration?(user) do
      false ->
        {:ok, user}

      true ->
        case User.RegistrationState.login_to_finish_registration?(user) do
          false ->
            {:ok, user}

          true ->
            # This happens when the user has been created via Google/Twitter OAuth
            # In such case the /auth/google or /auth/twitter endpoint does not return a
            # user (like in emailLoginVerify) and the first_login: true will be put
            # in the first `currentUser` call.
            case Sanbase.Accounts.forward_registration(user, "login", %{origin_url: origin_url}) do
              # :keep_state indicates that the change did not update because it has
              # been already changed by a concurrent request in the same or on
              # another node. :evolve state shows that this is the process that
              # updated the state, so this is the true first login
              {:ok, :evolve_state, user} -> {:ok, %{user | first_login: true}}
              {:ok, :keep_state, user} -> {:ok, user}
            end
        end
    end
  end

  def current_user(_root, _args, _context), do: {:ok, nil}

  def get_user(_root, %{selector: selector}, _resolution) when map_size(selector) != 1 do
    {:error, "Provide exactly one field in the user selector object"}
  end

  def get_user(_root, %{selector: selector}, _resolution) do
    User.by_selector(selector)
  end

  def following(%User{id: user_id}, _args, _resolution) do
    following = UserFollower.followed_by(user_id)

    {:ok, %{count: length(following), users: following}}
  end

  def following2(%User{id: user_id}, _args, _resolution) do
    following = UserFollower.followed_by2(user_id)

    {:ok, %{count: length(following), users: following}}
  end

  def followers(%User{id: user_id}, _args, _resolution) do
    followers = UserFollower.followers_of(user_id)

    {:ok, %{count: length(followers), users: followers}}
  end

  def followers2(%User{id: user_id}, _args, _resolution) do
    followers = UserFollower.followers_of2(user_id)

    {:ok, %{count: length(followers), users: followers}}
  end

  def queries_executions_info(_root, _args, %{context: %{auth: %{current_user: user}} = context}) do
    subscription_product = context.subscription_product
    plan_name = context.auth.plan

    with {:ok, details} <- Sanbase.Queries.user_executions_summary(user.id) do
      credits_limit = Sanbase.Queries.Authorization.credits_limit(subscription_product, plan_name)

      executions_limit =
        Sanbase.Queries.Authorization.query_executions_limit(subscription_product, plan_name)

      result = %{
        credits_availalbe_month: credits_limit,
        credits_spent_month: details.monthly_credits_spent,
        credits_remaining_month: credits_limit - details.monthly_credits_spent,
        queries_executed_month: details.queries_executed_month,
        queries_executed_day: details.queries_executed_day,
        queries_executed_hour: details.queries_executed_hour,
        queries_executed_minute: details.queries_executed_minute,
        queries_executed_day_limit: executions_limit.day,
        queries_executed_hour_limit: executions_limit.hour,
        queries_executed_minute_limit: executions_limit.minute
      }

      {:ok, result}
    end
  end

  def change_name(_root, %{name: new_name}, %{context: %{auth: %{current_user: user}}}) do
    case User.change_name(user, new_name) do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's name to #{new_name}",
          details: changeset_errors(changeset)
        }
    end
  end

  def change_username(_root, %{username: new_username}, %{context: %{auth: %{current_user: user}}}) do
    case User.change_username(user, new_username) do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's username to #{new_username}",
          details: changeset_errors(changeset)
        }
    end
  end

  def change_avatar(_root, %{avatar_url: avatar_url}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    User.update_avatar_url(user, avatar_url)
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot change the avatar", details: changeset_errors(changeset)
        }
    end
  end

  def self_reset_api_rate_limits(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    user = Sanbase.Repo.preload(user, :user_settings)

    with true <- UserSettings.can_self_reset_api_rate_limits?(user),
         {:ok, _acl} <- Sanbase.ApiCallLimit.reset(user),
         {:ok, _settings} <-
           UserSettings.update_self_reset_api_rate_limits_datetime(user, DateTime.utc_now()) do
      user = Sanbase.Repo.preload(user, :user_settings, force: true)
      {:ok, user}
    end
  end

  def add_user_eth_address(
        _root,
        %{signature: signature, address: address, message_hash: _message_hash},
        %{context: %{auth: %{auth_method: :user_token, current_user: user}}}
      ) do
    with true <- Ethauth.valid_signature?(address, signature),
         {:ok, _} <- Sanbase.Accounts.EthAccount.create(user.id, address) do
      {:ok, user}
    else
      {:error, error_or_changeset} ->
        reason =
          case error_or_changeset do
            %Ecto.Changeset{} = changeset -> changeset_errors_string(changeset)
            error -> inspect(error)
          end

        error_msg = "Could not add an ethereum address for user #{user.id}. Reason: #{reason}"
        Logger.warning(error_msg)
        {:error, error_msg}
    end
  end

  def remove_user_eth_address(_root, %{address: address}, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    case Sanbase.Accounts.EthAccount.remove(user.id, address) do
      true ->
        {:ok, user}

      {:error, reason} ->
        error_msg =
          "Could not remove an ethereum address for user #{user.id}. Reason: #{inspect(reason)}"

        {:error, error_msg}
    end
  end

  def update_terms_and_conditions(_root, args, %{
        context: %{auth: %{auth_method: :user_token, current_user: user}}
      }) do
    # Update only the provided arguments
    args =
      args
      |> Enum.reject(fn {_key, value} -> value == nil end)
      |> Enum.into(%{})

    user
    |> User.changeset(args)
    |> Sanbase.Repo.update()
    |> case do
      {:ok, user} ->
        {:ok, user}

      {:error, changeset} ->
        {
          :error,
          message: "Cannot update current user's terms and conditions",
          details: changeset_errors(changeset)
        }
    end
  end

  def user_promo_codes(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    {:ok, Sanbase.Billing.UserPromoCode.get_user_promo_codes(user.id)}
  end

  def user_promo_codes(%Sanbase.Accounts.User{} = user, _args, _resolution) do
    {:ok, Sanbase.Billing.UserPromoCode.get_user_promo_codes(user.id)}
  end

  def user_promo_codes(_, _, _) do
    {:ok, []}
  end

  def signup_datetime(_root, _args, %{context: %{auth: %{current_user: user}}}) do
    {:ok, User.get_signup_dt(user)}
  end

  def signup_datetime(%User{} = user, _args, _resolution) do
    {:ok, User.get_signup_dt(user)}
  end

  def user_no_preloads(%{user_id: user_id}, _args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(SanbaseDataloader, :users_by_id, user_id)
    |> on_load(fn loader ->
      {:ok, Dataloader.get(loader, SanbaseDataloader, :users_by_id, user_id)}
    end)
  end
end
