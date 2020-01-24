defmodule SanbaseWeb.Graphql.InsightTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.InsightResolver
  alias SanbaseWeb.Graphql.SanbaseRepo

  object :vote do
    field(:total_votes, non_null(:integer))
    field(:total_san_votes, non_null(:integer))
  end

  object :post do
    field(:id, non_null(:id))
    field(:user, non_null(:post_author), resolve: dataloader(SanbaseRepo))
    field(:title, non_null(:string))
    field(:short_desc, :string)
    field(:link, :string)
    field(:text, :string)
    field(:state, :string)
    field(:moderation_comment, :string)
    field(:ready_state, :string)
    field(:images, list_of(:image_data))
    field(:tags, list_of(:tag))

    field :comments_count, :integer do
      resolve(&InsightResolver.comments_count/3)
    end

    field :related_projects, list_of(:project) do
      resolve(&InsightResolver.related_projects/3)
    end

    field :published_at, :datetime do
      resolve(fn
        %{published_at: nil}, _, _ -> {:ok, nil}
        %{published_at: published_at}, _, _ -> DateTime.from_naive(published_at, "Etc/UTC")
      end)
    end

    field :created_at, non_null(:datetime) do
      resolve(fn %{inserted_at: inserted_at}, _, _ ->
        {:ok, inserted_at}
      end)
    end

    field(:updated_at, non_null(:datetime))

    field :voted_at, :datetime do
      resolve(&InsightResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&InsightResolver.votes/3)
    end
  end
end
