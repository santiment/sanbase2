defmodule SanbaseWeb.Graphql.AuthTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :auth_session do
    field(:type, non_null(:string))
    field(:jti, non_null(:string))
    field(:created_at, non_null(:datetime))
    field(:expires_at, non_null(:datetime))
    field(:last_active_at, non_null(:datetime))
    field(:platform, non_null(:string))
    field(:client, non_null(:string))
    field(:is_current, non_null(:boolean))
    field(:has_expired, non_null(:boolean))
  end

  object :login do
    field(:token, non_null(:string))
    field(:access_token, non_null(:string))
    field(:refresh_token, non_null(:string))
    field(:user, non_null(:user))
  end

  object :logout do
    field(:success, non_null(:boolean))
  end

  object :email_login_request do
    field(:success, non_null(:boolean))
    field(:first_login, :boolean, default_value: false)
  end
end
