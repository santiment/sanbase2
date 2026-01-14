defmodule SanbaseWeb.Graphql.AppNotificationTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.AppNotificationResolver

  object :app_notification do
    field(:id, non_null(:integer))
    field(:type, non_null(:string))
    field(:title, :string)
    field(:content, :string)
    field(:entity_type, :string)
    field(:entity_id, :integer)
    field(:entity_name, :string)
    field(:is_broadcast, non_null(:boolean))
    field(:json_data, :json)
    field(:inserted_at, non_null(:datetime))

    field :is_read, non_null(:boolean) do
      resolve(&AppNotificationResolver.is_read/3)
    end

    field(:read_at, :datetime)
    field(:user, :public_user)
  end

  object :app_notifications_paginated do
    field(:notifications, list_of(:app_notification))
    field(:cursor, :cursor)
  end
end
