defmodule SanbaseWeb.Graphql.SocialDataTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.SocialDataResolver
  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  enum :trending_words_source do
    value(:telegram)
    value(:twitter_crypto)
    value(:reddit)
    value(:all)
  end

  enum :social_dominance_sources do
    value(:telegram)
    value(:reddit)
    value(:all)
  end

  enum :social_gainers_losers_status_enum do
    value(:gainer)
    value(:loser)
    value(:newcomer)
    value(:all)
  end

  enum :social_volume_type do
    value(:reddit_comments_overview)
    value(:telegram_chats_overview)
    value(:telegram_discussion_overview)
  end

  enum :topic_search_sources do
    value(:telegram)
    value(:reddit)
  end

  object :popular_search_term do
    field(:title, non_null(:string))
    field(:options, :json)
    field(:datetime, non_null(:datetime))
    field(:search_term, non_null(:string))
    field(:selector_type, non_null(:string))
    field(:updated_at, :datetime)

    field :created_at, non_null(:datetime) do
      resolve(fn %{inserted_at: inserted_at}, _, _ ->
        {:ok, inserted_at}
      end)
    end
  end

  object :topic_search do
    field(:chart_data, list_of(:chart_data))
  end

  object :messages do
    field(:text, :string)
    field(:datetime, non_null(:datetime))
  end

  object :chart_data do
    field(:mentions_count, :float)
    field(:datetime, non_null(:datetime))
  end

  object :social_volume do
    field(:datetime, non_null(:datetime))
    field(:mentions_count, :integer)
  end

  object :social_dominance do
    field(:datetime, non_null(:datetime))
    field(:dominance, :float)
  end

  object :trending_word_summary do
    field(:source, non_null(:string))
    field(:datetime, non_null(:datetime))
    field(:summary, non_null(:string))
  end

  object :trending_words do
    field(:datetime, non_null(:datetime))
    field(:top_words, list_of(:word_with_context))
  end

  object :trending_word_position do
    field(:datetime, non_null(:datetime))
    field(:position, :integer)
  end

  object :word_with_context do
    field(:context, list_of(:word_context))
    field(:score, non_null(:float))
    field(:word, non_null(:string))
    field(:summary, non_null(:string))
    field(:summaries, list_of(:trending_word_summary))
  end

  object :word_trend_score do
    field(:datetime, non_null(:datetime))
    field(:score, non_null(:float))
    field(:source, :trending_words_source)
  end

  object :word_context do
    field(:word, non_null(:string))
    field(:score, non_null(:float))
  end

  object :words_context do
    field(:word, non_null(:string))
    field(:context, list_of(:word_context))
  end

  object :words_social_volume do
    field(:word, non_null(:string))
    field(:timeseries_data, list_of(:social_volume))
  end

  object :words_social_dominance do
    field(:word, non_null(:string))
    field(:social_dominance, non_null(:float))
  end

  object :top_social_gainers_losers do
    field(:datetime, non_null(:datetime))
    field(:projects, list_of(:projects_change))
  end

  object :projects_change do
    field(:slug, non_null(:string))

    field :project, :project do
      cache_resolve(&SocialDataResolver.project_from_slug/3)
    end

    field(:change, non_null(:float))
    field(:status, :social_gainers_losers_status_enum)
  end

  object :social_gainers_losers_status do
    field(:datetime, non_null(:datetime))
    field(:change, non_null(:float))
    field(:status, :social_gainers_losers_status_enum)
  end

  input_object :word_selector_input_object do
    field(:word, :string)
    field(:words, list_of(:string))
  end
end
