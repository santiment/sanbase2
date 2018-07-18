defmodule SanbaseWeb.Graphql.VotingTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.Resolvers.{VotingResolver, PostResolver}
  alias SanbaseWeb.Graphql.SanbaseRepo

  object :vote do
    field(:total_votes, non_null(:integer))
    field(:total_san_votes, non_null(:integer))
  end

  object :tag do
    field(:name, non_null(:string))
  end

  object :poll do
    field(:start_at, non_null(:datetime))
    field(:end_at, non_null(:datetime))
    field(:posts, list_of(:post))
  end

  object :post do
    field(:id, non_null(:id))
    field(:user, non_null(:post_author), resolve: dataloader(SanbaseRepo))
    field(:poll, non_null(:poll))
    field(:title, non_null(:string))
    field(:short_desc, :string)
    field(:link, :string)
    field(:text, :string)
    field(:state, :string)
    field(:moderation_comment, :string)
    field(:ready_state, :string)
    field(:images, list_of(:image_data), resolve: dataloader(SanbaseRepo))
    field(:tags, list_of(:tag), resolve: dataloader(SanbaseRepo))
    field(:discourse_topic_url, :string)

    field :related_projects, list_of(:project) do
      resolve(&PostResolver.related_projects/3)
    end

    field :created_at, non_null(:datetime) do
      resolve(fn %{inserted_at: inserted_at}, _, _ ->
        {:ok, inserted_at}
      end)
    end

    field :voted_at, :datetime do
      resolve(&VotingResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&VotingResolver.votes/3)
    end
  end
end
