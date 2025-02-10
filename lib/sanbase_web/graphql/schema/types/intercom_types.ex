defmodule SanbaseWeb.Graphql.IntercomTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :user_attribute do
    field(:user_id, :id)
    field(:inserted_at, :datetime)
    field(:properties, :json)
  end

  object :user_event do
    field(:user_id, :id)
    field(:created_at, :datetime)
    field(:event_name, :string)
    field(:metadata, :json)
  end

  object :api_metric_distribution_per_user do
    field(:user_id, :id)
    field(:metrics, list_of(:metrics_count))
    field(:count, :integer)
  end

  object :metrics_count do
    field(:metric, :string)
    field(:count, :integer)
  end
end
