defmodule SanbaseWeb.Graphql.Schema.UserQueries do
  @moduledoc ~s"""
  Queries and mutations for working user accounts and settings
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.{
    AccountResolver,
    ApikeyResolver,
    UserSettingsResolver,
    TelegramResolver,
    UserFollowerResolver
  }

  alias SanbaseWeb.Graphql.Middlewares.{
    JWTAuth,
    CreateOrDeleteSession
  }

  object :user_queries do
    @desc "Returns the user currently logged in."
    field :current_user, :user do
      resolve(&AccountResolver.current_user/3)
    end

    @desc """
    Get a URL for deep-linking sanbase and telegram accounts. It carries a unique
    random token that is associated with the user. The link leads to a telegram chat
    with Santiment's notification bot. When the `Start` button is pressed, telegram
    and sanbase accounts are linked and the user can receive sanbase signals in telegram.
    """
    field :get_telegram_deep_link, :string do
      middleware(JWTAuth)
      resolve(&TelegramResolver.get_telegram_deep_link/3)
    end
  end

  object :user_mutations do
    field :eth_login, :login do
      arg(:signature, non_null(:string))
      arg(:address, non_null(:string))
      arg(:message_hash, non_null(:string))

      resolve(&AccountResolver.eth_login/2)
      middleware(CreateOrDeleteSession)
    end

    field :email_login, :email_login_request do
      arg(:email, non_null(:string))
      arg(:username, :string)
      arg(:consent, :string)

      resolve(&AccountResolver.email_login/2)
    end

    field :email_login_verify, :login do
      arg(:email, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&AccountResolver.email_login_verify/2)
      middleware(CreateOrDeleteSession)
    end

    field :logout, :logout do
      middleware(JWTAuth, allow_access: true)
      resolve(fn _, _ -> {:ok, %{success: true}} end)
      middleware(CreateOrDeleteSession)
    end

    field :email_change_verify, :login do
      arg(:email_candidate, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&AccountResolver.email_change_verify/2)
    end

    field :change_email, :email_login_request do
      arg(:email, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_email/3)
    end

    field :change_username, :user do
      arg(:username, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.change_username/3)
    end

    @desc ~s"""
    Add the given `address` for the currently logged in user. The `signature` and
    `message_hash` are passed to the `web3.eth.accounts.recover` function to recover
    the Ethereum address. If it is the same as the passed in the argument then the
    user has access to this address and has indeed signed the message
    """
    field :add_user_eth_address, :user do
      arg(:signature, non_null(:string))
      arg(:address, non_null(:string))
      arg(:message_hash, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.add_user_eth_address/3)
    end

    @desc ~s"""
    Remove the given `address` for the currently logged in user. This can only be done
    if this `address` is not the only mean for the user to log in. It can be removed
    only if there is an email set or there is another ethereum address added.
    """
    field :remove_user_eth_address, :user do
      arg(:address, non_null(:string))

      middleware(JWTAuth)
      resolve(&AccountResolver.remove_user_eth_address/3)
    end

    @desc ~s"""
    Update the terms and condition the user accepts. The `accept_privacy_policy`
    must be accepted (must equal `true`) in order for the account to be considered
    activated.
    """
    field :update_terms_and_conditions, :user do
      arg(:privacy_policy_accepted, :boolean)
      arg(:marketing_accepted, :boolean)

      # Allow this mutation to be executed when the user has not accepted the privacy policy.
      middleware(JWTAuth, allow_access: true)
      resolve(&AccountResolver.update_terms_and_conditions/3)
    end

    @desc ~s"""
    Generates a new apikey. There could be more than one apikey per user at every
    given time. Only JWT authenticated users can generate apikeys. The apikeys can
     be retrieved via the `apikeys` fields of the `user` GQL type.
    """
    field :generate_apikey, :user do
      middleware(JWTAuth)
      resolve(&ApikeyResolver.generate_apikey/3)
    end

    @desc ~s"""
    Revoke the given apikey if only the currently logged in user is the owner of the
    apikey. Only JWT authenticated users can revoke apikeys. You cannot revoke the apikey
    using the apikey.
    """
    field :revoke_apikey, :user do
      arg(:apikey, non_null(:string))

      middleware(JWTAuth)
      resolve(&ApikeyResolver.revoke_apikey/3)
    end

    @desc "Allow/Dissallow to receive notifications in email/telegram channel"
    field :settings_toggle_channel, :user_settings do
      arg(:signal_notify_telegram, :boolean)
      arg(:signal_notify_email, :boolean)

      middleware(JWTAuth)
      resolve(&UserSettingsResolver.settings_toggle_channel/3)
    end

    @desc "Change subscription to Santiment newsletter"
    field :change_newsletter_subscription, :user_settings do
      arg(:newsletter_subscription, :newsletter_subscription_type)

      middleware(JWTAuth)
      resolve(&UserSettingsResolver.change_newsletter_subscription/3)
    end

    @desc """
    Revoke the telegram deep link for the currently logged in user if present.
    The link will continue to work and following it will send a request to sanbase,
    but the used token will no longer be paired with the user.
    """
    field :revoke_telegram_deep_link, :boolean do
      middleware(JWTAuth)
      resolve(&TelegramResolver.revoke_telegram_deep_link/3)
    end

    @desc "Follow chosen user"
    field :follow, :user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&UserFollowerResolver.follow/3)
    end

    @desc "Unfollow chosen user"
    field :unfollow, :user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&UserFollowerResolver.unfollow/3)
    end
  end
end
