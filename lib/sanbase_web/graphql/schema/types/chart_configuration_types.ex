defmodule SanbaseWeb.Graphql.ChartConfigurationTypes do
  use Absinthe.Schema.Notation
  import Absinthe.Resolution.Helpers, only: [dataloader: 1]

  alias SanbaseWeb.Graphql.SanbaseRepo
  alias SanbaseWeb.Graphql.Resolvers.ChartConfigurationResolver

  input_object :project_chart_input_object do
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:metrics, list_of(:string))
    field(:anomalies, list_of(:string))
    field(:queries, :json)
    field(:drawings, :json)
    field(:options, :json)
    field(:project_id, :integer)
    field(:post_id, :integer)
  end

  object :chart_configuration do
    field(:id, non_null(:integer))
    field(:title, :string)
    field(:description, :string)
    field(:is_public, :boolean)
    field(:metrics, list_of(:string))
    field(:anomalies, list_of(:string))
    field(:queries, :json)
    field(:drawings, :json)
    field(:options, :json)

    field(:user, :user, resolve: dataloader(SanbaseRepo))
    field(:project, :project, resolve: dataloader(SanbaseRepo))
    field(:post, :post, resolve: dataloader(SanbaseRepo))

    field(:chart_events, list_of(:post))

    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)

    field :comments_count, :integer do
      resolve(&ChartConfigurationResolver.comments_count/3)
    end
  end
end
