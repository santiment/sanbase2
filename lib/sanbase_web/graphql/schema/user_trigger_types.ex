defmodule SanbaseWeb.Graphql.UserTriggerTypes do
  use Absinthe.Schema.Notation

  object :user_trigger do
    field(:user_id, :integer)
    field(:trigger, :trigger)
  end

  object :trigger do
    field(:id, :string)
    field(:title, :string)
    field(:description, :string)
    field(:icon_url, :string)
    field(:settings, :json)
    field(:is_public, :boolean)
    field(:cooldown, :integer)
    field(:tags, list_of(:tag))
  end
end
