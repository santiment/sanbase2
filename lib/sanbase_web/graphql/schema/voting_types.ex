defmodule SanbaseWeb.Graphql.VotingTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.VotingResolver

  object :poll do
    field(:start_at, non_null(:datetime))
    field(:end_at, non_null(:datetime))
    field(:posts, list_of(:post))
  end

  object :post do
    field(:id, non_null(:id))
    field(:user, non_null(:user))
    field(:poll, non_null(:poll))
    field(:title, non_null(:string))
    field(:link, non_null(:string))
    field(:state, :string)
    field(:moderation_comment, :string)

    field :created_at, non_null(:datetime) do
      resolve(fn %{inserted_at: inserted_at}, _, _ ->
        {:ok, inserted_at}
      end)
    end

    field :voted_at, :datetime do
      resolve(&VotingResolver.voted_at/3)
    end

    field :total_san_votes, :integer do
      resolve(&VotingResolver.total_san_votes/3)
    end
  end
end
