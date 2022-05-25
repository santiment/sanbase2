defmodule SanbaseWeb.Graphql.Schema.UserQueries do
  @moduledoc ~s"""
  Queries and mutations for working user accounts and settings
  """
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.{
    AccessControlResolver,
    ApikeyResolver,
    TelegramResolver,
    UserFollowerResolver,
    UserResolver,
    UserSettingsResolver
  }

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

  object :user_queries do
    @desc "Returns the user currently logged in."
    field :current_user, :user do
      meta(access: :free)

      resolve(&UserResolver.current_user/3)
    end

    @desc "Returns the selected."
    field :get_user, :public_user do
      arg(:selector, non_null(:user_selector_input_object))

      meta(access: :free)

      resolve(&UserResolver.get_user/3)
    end

    field :is_telegram_chat_id_valid, :boolean do
      meta(access: :free)
      arg(:chat_id, non_null(:string))

      middleware(JWTAuth)
      resolve(&TelegramResolver.is_telegram_chat_id_valid/3)
    end

    @desc """
    Get a URL for deep-linking sanbase and telegram accounts. It carries a unique
    random token that is associated with the user. The link leads to a telegram chat
    with Santiment's notification bot. When the `Start` button is pressed, telegram
    and sanbase accounts are linked and the user can receive sanbase alerts in telegram.
    """
    field :get_telegram_deep_link, :string do
      meta(access: :free)

      middleware(JWTAuth)
      resolve(&TelegramResolver.get_telegram_deep_link/3)
    end

    field :get_access_restrictions, list_of(:access_restriction) do
      meta(access: :free)

      arg(:product, :products_enum)
      arg(:plan, :plans_enum)

      resolve(&AccessControlResolver.get_access_restrictions/3)
    end
  end

  object :user_mutations do
    @desc ~s"""
    Verifies that the email change is valid. This mutation does the actual email change.
    """
    field :email_change_verify, :login do
      arg(:email_candidate, non_null(:string))
      arg(:token, non_null(:string))

      resolve(&UserResolver.email_change_verify/2)
    end

    @desc ~s"""
    Initiate the email change process. This mutation will send an email that contains
    a link that needs to be followed to complete the email change.
    """
    field :change_email, :email_login_request do
      arg(:email, non_null(:string))

      middleware(JWTAuth)
      resolve(&UserResolver.change_email/3)
    end

    field :change_username, :user do
      arg(:username, non_null(:string))

      middleware(JWTAuth, allow_access_without_terms_accepted: true)
      resolve(&UserResolver.change_username/3)
    end

    field :change_name, :user do
      arg(:name, non_null(:string))

      middleware(JWTAuth)
      resolve(&UserResolver.change_name/3)
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
      resolve(&UserResolver.add_user_eth_address/3)
    end

    @desc ~s"""
    Remove the given `address` for the currently logged in user. This can only be done
    if this `address` is not the only mean for the user to log in. It can be removed
    only if there is an email set or there is another ethereum address added.
    """
    field :remove_user_eth_address, :user do
      arg(:address, non_null(:string))

      middleware(JWTAuth)
      resolve(&UserResolver.remove_user_eth_address/3)
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
      middleware(JWTAuth, allow_access_without_terms_accepted: true)
      resolve(&UserResolver.update_terms_and_conditions/3)
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
      arg(:alert_notify_telegram, :boolean)
      arg(:signal_notify_telegram, :boolean)

      arg(:alert_notify_email, :boolean)
      arg(:signal_notify_email, :boolean)

      middleware(JWTAuth)
      resolve(&UserSettingsResolver.settings_toggle_channel/3)
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

    @desc "Follow a chosen user"
    field :follow, :user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&UserFollowerResolver.follow/3)
    end

    @desc "Unfollow a chosen user"
    field :unfollow, :user do
      arg(:user_id, non_null(:id))

      middleware(JWTAuth)
      resolve(&UserFollowerResolver.unfollow/3)
    end

    field :following_toggle_notification, :user do
      arg(:user_id, non_null(:id))
      arg(:disable_notifications, :boolean, default_value: false)

      middleware(JWTAuth)

      resolve(&UserFollowerResolver.following_toggle_notification/3)
    end

    field :update_user_settings, :user_settings do
      arg(:settings, :user_settings_input_object)
      middleware(JWTAuth)
      resolve(&UserSettingsResolver.update_user_settings/3)
    end

    @desc "Change the user's avatar."
    field :change_avatar, :user do
      arg(:avatar_url, non_null(:string))

      middleware(JWTAuth)
      resolve(&UserResolver.change_avatar/3)
    end
  end
end
