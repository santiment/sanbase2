defmodule SanbaseWeb.Graphql.InsightTypes do
  use Absinthe.Schema.Notation

  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.Resolvers.{InsightResolver, VoteResolver, UserResolver}
  alias SanbaseWeb.Graphql.SanbaseRepo

  object :metric_short_description do
    field(:name, non_null(:string))
  end

  object :highlighted_text do
    field(:highlight, non_null(:boolean))
    field(:text, non_null(:string))
  end

  object :post_highlights do
    field(:title, list_of(:highlighted_text))
    field(:text, list_of(:highlighted_text))
    field(:tags, list_of(:highlighted_text))
    field(:metrics, list_of(:highlighted_text))
  end

  object :post_search do
    field(:post, non_null(:post))
    field(:highlights, :post_highlights)
  end

  object :post_image_data do
    field(:image_url, non_null(:string))
  end

  object :post do
    field(:id, non_null(:integer))

    field :user, non_null(:public_user) do
      resolve(&UserResolver.user_no_preloads/3)
    end

    field(:title, non_null(:sanitized_string_no_tags))
    field(:short_desc, :sanitized_html_subset_string)
    field(:text, :sanitized_html_subset_string)

    field :pulse_text, :sanitized_html_subset_string do
      resolve(&InsightResolver.pulse_text/3)
    end

    field(:state, :string)
    field(:moderation_comment, :string)
    field(:ready_state, :string)

    field :images, list_of(:post_image_data) do
      resolve(&InsightResolver.extract_images_from_text/3)
    end

    field(:tags, list_of(:tag))
    field(:metrics, list_of(:metric_short_description), resolve: dataloader(SanbaseRepo))
    field(:price_chart_project, :project, resolve: dataloader(SanbaseRepo))
    field(:prediction, :string)
    field(:is_pulse, :boolean)
    field(:is_hidden, non_null(:boolean))
    field(:is_featured, :boolean)
    field(:is_paywall_required, :boolean)
    field(:is_chart_event, :boolean)
    field(:chart_event_datetime, :datetime)
    field(:chart_configuration_for_event, :chart_configuration)
    field(:views, :integer)

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
      resolve(&VoteResolver.voted_at/3)
    end

    field :votes, :vote do
      resolve(&VoteResolver.votes/3)
    end
  end
end
