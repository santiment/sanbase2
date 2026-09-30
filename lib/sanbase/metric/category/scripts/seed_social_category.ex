defmodule Sanbase.Metric.Category.Scripts.SeedSocialCategory do
  @moduledoc ~s"""
  Creates the "Social" metric category and puts the social metrics in it, ungrouped.
  `Sanbase.Metric.Category.TaxonomyImporter.apply!(["social"])` then sorts them into
  groups - it only works with metrics that already have a row in the category.

  Run it from an iex shell:

      # See what would change, write nothing
      Sanbase.Metric.Category.Scripts.SeedSocialCategory.plan()

      # Write
      Sanbase.Metric.Category.Scripts.SeedSocialCategory.apply!()

  The file is self-contained, so it can be pasted into `bin/sanbase remote` before
  it is deployed.

  Idempotent: a metric that already has a row in the category, grouped or not, is
  left alone. A registry metric (or registry alias) is mapped by its registry id,
  any other metric by the module that serves it. A name that is neither is
  reported and skipped.
  """

  import Ecto.Query

  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo

  @category "Social"

  @metrics [
    "community_messages_count_reddit",
    "community_messages_count_telegram",
    "community_messages_count_total",
    "community_social_volume_reddit",
    "community_social_volume_telegram",
    "integral_sentiment_bb",
    "integral_sentiment_bb_1d",
    "integral_sentiment_bb_1h",
    "mentions_count_4chan",
    "mentions_count_bitcointalk",
    "mentions_count_farcaster",
    "mentions_count_reddit",
    "mentions_count_telegram",
    "mentions_count_total",
    "mentions_count_twitter",
    "mentions_percentage_1h_total",
    "mentions_percentage_4chan",
    "mentions_percentage_bitcointalk",
    "mentions_percentage_farcaster",
    "mentions_percentage_reddit",
    "mentions_percentage_telegram",
    "mentions_percentage_total",
    "mentions_percentage_twitter",
    "negative_docs_count_4chan",
    "negative_docs_count_farcaster",
    "negative_docs_count_reddit",
    "negative_docs_count_telegram",
    "negative_docs_count_total",
    "negative_docs_count_twitter",
    "neutral_docs_count_4chan",
    "neutral_docs_count_farcaster",
    "neutral_docs_count_reddit",
    "neutral_docs_count_telegram",
    "neutral_docs_count_total",
    "neutral_docs_count_twitter",
    "nft_social_volume",
    "positive_docs_count_4chan",
    "positive_docs_count_farcaster",
    "positive_docs_count_reddit",
    "positive_docs_count_telegram",
    "positive_docs_count_total",
    "positive_docs_count_twitter",
    "sentiment_balance_4chan",
    "sentiment_balance_bitcointalk",
    "sentiment_balance_discord",
    "sentiment_balance_farcaster",
    "sentiment_balance_professional_traders_chat",
    "sentiment_balance_reddit",
    "sentiment_balance_telegram",
    "sentiment_balance_total",
    "sentiment_balance_total_change_{{interval}}",
    "sentiment_balance_twitter",
    "sentiment_balance_twitter_crypto",
    "sentiment_balance_twitter_news",
    "sentiment_balance_twitter_nft",
    "sentiment_balance_youtube_videos",
    "sentiment_bb_ratio_selective",
    "sentiment_bearish_4chan",
    "sentiment_bearish_bitcointalk",
    "sentiment_bearish_farcaster",
    "sentiment_bearish_reddit",
    "sentiment_bearish_telegram",
    "sentiment_bearish_total",
    "sentiment_bearish_twitter",
    "sentiment_bearish_youtube_videos",
    "sentiment_bullish_4chan",
    "sentiment_bullish_bitcointalk",
    "sentiment_bullish_farcaster",
    "sentiment_bullish_reddit",
    "sentiment_bullish_telegram",
    "sentiment_bullish_total",
    "sentiment_bullish_twitter",
    "sentiment_bullish_youtube_videos",
    "sentiment_negative_4chan",
    "sentiment_negative_bitcointalk",
    "sentiment_negative_discord",
    "sentiment_negative_farcaster",
    "sentiment_negative_professional_traders_chat",
    "sentiment_negative_ratio_4chan",
    "sentiment_negative_ratio_4chan_1d",
    "sentiment_negative_ratio_4chan_1h",
    "sentiment_negative_ratio_farcaster",
    "sentiment_negative_ratio_farcaster_1d",
    "sentiment_negative_ratio_farcaster_1h",
    "sentiment_negative_ratio_reddit",
    "sentiment_negative_ratio_reddit_1d",
    "sentiment_negative_ratio_reddit_1h",
    "sentiment_negative_ratio_telegram",
    "sentiment_negative_ratio_telegram_1d",
    "sentiment_negative_ratio_telegram_1h",
    "sentiment_negative_ratio_total",
    "sentiment_negative_ratio_total_1d",
    "sentiment_negative_ratio_total_1h",
    "sentiment_negative_ratio_twitter",
    "sentiment_negative_ratio_twitter_1d",
    "sentiment_negative_ratio_twitter_1h",
    "sentiment_negative_reddit",
    "sentiment_negative_telegram",
    "sentiment_negative_total",
    "sentiment_negative_twitter",
    "sentiment_negative_twitter_crypto",
    "sentiment_negative_twitter_news",
    "sentiment_negative_twitter_nft",
    "sentiment_negative_youtube_videos",
    "sentiment_neutral_4chan",
    "sentiment_neutral_bitcointalk",
    "sentiment_neutral_farcaster",
    "sentiment_neutral_ratio_4chan",
    "sentiment_neutral_ratio_4chan_1d",
    "sentiment_neutral_ratio_4chan_1h",
    "sentiment_neutral_ratio_farcaster",
    "sentiment_neutral_ratio_farcaster_1d",
    "sentiment_neutral_ratio_farcaster_1h",
    "sentiment_neutral_ratio_reddit",
    "sentiment_neutral_ratio_reddit_1d",
    "sentiment_neutral_ratio_reddit_1h",
    "sentiment_neutral_ratio_telegram",
    "sentiment_neutral_ratio_telegram_1d",
    "sentiment_neutral_ratio_telegram_1h",
    "sentiment_neutral_ratio_total",
    "sentiment_neutral_ratio_total_1d",
    "sentiment_neutral_ratio_total_1h",
    "sentiment_neutral_ratio_twitter",
    "sentiment_neutral_ratio_twitter_1d",
    "sentiment_neutral_ratio_twitter_1h",
    "sentiment_neutral_reddit",
    "sentiment_neutral_telegram",
    "sentiment_neutral_total",
    "sentiment_neutral_twitter",
    "sentiment_neutral_youtube_videos",
    "sentiment_positive_4chan",
    "sentiment_positive_bitcointalk",
    "sentiment_positive_discord",
    "sentiment_positive_farcaster",
    "sentiment_positive_professional_traders_chat",
    "sentiment_positive_ratio_4chan",
    "sentiment_positive_ratio_4chan_1d",
    "sentiment_positive_ratio_4chan_1h",
    "sentiment_positive_ratio_farcaster",
    "sentiment_positive_ratio_farcaster_1d",
    "sentiment_positive_ratio_farcaster_1h",
    "sentiment_positive_ratio_reddit",
    "sentiment_positive_ratio_reddit_1d",
    "sentiment_positive_ratio_reddit_1h",
    "sentiment_positive_ratio_telegram",
    "sentiment_positive_ratio_telegram_1d",
    "sentiment_positive_ratio_telegram_1h",
    "sentiment_positive_ratio_total",
    "sentiment_positive_ratio_total_1d",
    "sentiment_positive_ratio_total_1h",
    "sentiment_positive_ratio_twitter",
    "sentiment_positive_ratio_twitter_1d",
    "sentiment_positive_ratio_twitter_1h",
    "sentiment_positive_reddit",
    "sentiment_positive_telegram",
    "sentiment_positive_total",
    "sentiment_positive_twitter",
    "sentiment_positive_twitter_crypto",
    "sentiment_positive_twitter_news",
    "sentiment_positive_twitter_nft",
    "sentiment_positive_youtube_videos",
    "sentiment_volume_consumed_discord",
    "sentiment_volume_consumed_farcaster",
    "sentiment_volume_consumed_professional_traders_chat",
    "sentiment_volume_consumed_total_change_{{interval}}",
    "sentiment_volume_consumed_twitter_crypto",
    "sentiment_volume_consumed_twitter_news",
    "sentiment_volume_consumed_twitter_nft",
    "sentiment_weighted_4chan",
    "sentiment_weighted_4chan_1d",
    "sentiment_weighted_4chan_1h",
    "sentiment_weighted_bitcointalk",
    "sentiment_weighted_bitcointalk_1d",
    "sentiment_weighted_bitcointalk_1h",
    "sentiment_weighted_farcaster",
    "sentiment_weighted_farcaster_1d",
    "sentiment_weighted_farcaster_1h",
    "sentiment_weighted_reddit",
    "sentiment_weighted_reddit_1d",
    "sentiment_weighted_reddit_1h",
    "sentiment_weighted_telegram",
    "sentiment_weighted_telegram_1d",
    "sentiment_weighted_telegram_1h",
    "sentiment_weighted_total",
    "sentiment_weighted_total_1d",
    "sentiment_weighted_total_1h",
    "sentiment_weighted_twitter",
    "sentiment_weighted_twitter_1d",
    "sentiment_weighted_twitter_1h",
    "sentiment_weighted_youtube_videos",
    "sentiment_weighted_youtube_videos_1d",
    "sentiment_weighted_youtube_videos_1h",
    "social_active_users",
    "social_dominance_4chan",
    "social_dominance_4chan_1h_moving_average",
    "social_dominance_4chan_24h_moving_average",
    "social_dominance_ai_total",
    "social_dominance_ai_total_1h_moving_average",
    "social_dominance_ai_total_24h_moving_average",
    "social_dominance_bitcointalk",
    "social_dominance_bitcointalk_1h_moving_average",
    "social_dominance_bitcointalk_24h_moving_average",
    "social_dominance_discord",
    "social_dominance_farcaster",
    "social_dominance_farcaster_1h_moving_average",
    "social_dominance_farcaster_24h_moving_average",
    "social_dominance_professional_traders_chat",
    "social_dominance_reddit",
    "social_dominance_reddit_1h_moving_average",
    "social_dominance_reddit_24h_moving_average",
    "social_dominance_telegram",
    "social_dominance_telegram_1h_moving_average",
    "social_dominance_telegram_24h_moving_average",
    "social_dominance_total",
    "social_dominance_total_1h_moving_average",
    "social_dominance_total_1h_moving_average_change_{{interval}}",
    "social_dominance_total_24h_moving_average",
    "social_dominance_total_24h_moving_average_change_{{interval}}",
    "social_dominance_total_change_{{interval}}",
    "social_dominance_twitter",
    "social_dominance_twitter_1h_moving_average",
    "social_dominance_twitter_24h_moving_average",
    "social_dominance_twitter_crypto",
    "social_dominance_twitter_crypto_1h_moving_average",
    "social_dominance_twitter_crypto_24h_moving_average",
    "social_dominance_twitter_news",
    "social_dominance_twitter_news_1h_moving_average",
    "social_dominance_twitter_news_24h_moving_average",
    "social_dominance_twitter_nft",
    "social_dominance_twitter_nft_1h_moving_average",
    "social_dominance_twitter_nft_24h_moving_average",
    "social_dominance_youtube_videos",
    "social_dominance_youtube_videos_1h_moving_average",
    "social_dominance_youtube_videos_24h_moving_average",
    "social_volume_4chan",
    "social_volume_ai_total",
    "social_volume_bitcointalk",
    "social_volume_discord",
    "social_volume_farcaster",
    "social_volume_professional_traders_chat",
    "social_volume_reddit",
    "social_volume_telegram",
    "social_volume_total",
    "social_volume_total_change_{{interval}}",
    "social_volume_twitter",
    "social_volume_twitter_btc_maxi",
    "social_volume_twitter_builder",
    "social_volume_twitter_crypto",
    "social_volume_twitter_kol",
    "social_volume_twitter_media",
    "social_volume_twitter_memecoins",
    "social_volume_twitter_news",
    "social_volume_twitter_nft",
    "social_volume_twitter_trader",
    "social_volume_twitter_trading_firm",
    "social_volume_youtube_videos",
    "trending_words_rank",
    "twitter_followers",
    "unique_social_volume_4chan_1d",
    "unique_social_volume_4chan_1h",
    "unique_social_volume_4chan_5m",
    "unique_social_volume_bitcointalk_1d",
    "unique_social_volume_bitcointalk_1h",
    "unique_social_volume_bitcointalk_5m",
    "unique_social_volume_farcaster_1d",
    "unique_social_volume_farcaster_1h",
    "unique_social_volume_farcaster_5m",
    "unique_social_volume_reddit_1d",
    "unique_social_volume_reddit_1h",
    "unique_social_volume_reddit_5m",
    "unique_social_volume_telegram_1d",
    "unique_social_volume_telegram_1h",
    "unique_social_volume_telegram_5m",
    "unique_social_volume_total_1d",
    "unique_social_volume_total_1h",
    "unique_social_volume_total_5m",
    "unique_social_volume_twitter_1d",
    "unique_social_volume_twitter_1h",
    "unique_social_volume_twitter_5m"
  ]

  def metrics(), do: @metrics

  @doc "Compute and print what apply!/0 would do. Writes nothing."
  def plan() do
    plan = build_plan()
    IO.puts(report(plan))
    plan
  end

  @doc "Create the category, if needed, and the missing mappings in one transaction."
  def apply!() do
    {:ok, plan} =
      Repo.transaction(fn ->
        plan = build_plan()
        category = plan.category || create_category!()
        first_display_order = max_display_order(category.id) + 1

        plan.inserts
        |> Enum.with_index(first_display_order)
        |> Enum.each(fn {{_name, identity}, display_order} ->
          attrs = Map.merge(identity, %{category_id: category.id, display_order: display_order})

          %MetricCategoryMapping{}
          |> MetricCategoryMapping.changeset(attrs)
          |> Repo.insert!()
        end)

        plan
      end)

    IO.puts(report(plan))
    :ok
  end

  defp build_plan() do
    category = Repo.get_by(MetricCategory, name: @category)
    mapped = if category, do: mapped_identities(category.id), else: MapSet.new()
    registry_ids = registry_ids_by_name()

    {resolved, unknown} =
      @metrics
      |> Enum.map(&{&1, identity(&1, registry_ids)})
      |> Enum.split_with(fn {_name, identity} -> identity != nil end)

    {already_mapped, inserts} =
      Enum.split_with(resolved, fn {_name, identity} -> identity in mapped end)

    %{
      category: category,
      inserts: inserts,
      already_mapped: Enum.map(already_mapped, &elem(&1, 0)),
      unknown: Enum.map(unknown, &elem(&1, 0))
    }
  end

  # Aliases point at the row they belong to. A name that is on more than one row
  # (the same metric as a timeseries and as a histogram) prefers the timeseries -
  # those rows come last, so Map.new/1 keeps them.
  defp registry_ids_by_name() do
    Sanbase.Metric.Registry.all()
    |> Enum.sort_by(&(&1.data_type == "timeseries"))
    |> Enum.flat_map(fn registry ->
      [registry.metric | Enum.map(registry.aliases, & &1.name)]
      |> Enum.map(&{&1, registry.id})
    end)
    |> Map.new()
  end

  defp identity(name, registry_ids) do
    case Map.fetch(registry_ids, name) do
      {:ok, id} ->
        %{metric_registry_id: id}

      :error ->
        case Sanbase.Metric.get_module(name) do
          nil -> nil
          module -> %{module: inspect(module), metric: name}
        end
    end
  end

  defp mapped_identities(category_id) do
    from(m in MetricCategoryMapping,
      where: m.category_id == ^category_id,
      select: {m.metric_registry_id, m.module, m.metric}
    )
    |> Repo.all()
    |> MapSet.new(fn
      {id, nil, nil} -> %{metric_registry_id: id}
      {nil, module, metric} -> %{module: module, metric: metric}
    end)
  end

  defp max_display_order(category_id) do
    from(m in MetricCategoryMapping,
      where: m.category_id == ^category_id,
      select: max(m.display_order)
    )
    |> Repo.one() || 0
  end

  defp create_category!() do
    display_order = (Repo.one(from(c in MetricCategory, select: max(c.display_order))) || 0) + 1

    %MetricCategory{}
    |> MetricCategory.changeset(%{name: @category, display_order: display_order})
    |> Repo.insert!()
  end

  defp report(plan) do
    category =
      case plan.category do
        nil -> "#{@category} (will be created)"
        category -> "#{@category} (id #{category.id})"
      end

    unknown =
      if plan.unknown == [],
        do: "",
        else: "\n  unknown (skipped): #{Enum.join(plan.unknown, ", ")}"

    """
    Category: #{category}
      metrics in the list: #{length(@metrics)}
      already in the category: #{length(plan.already_mapped)}
      new mappings: #{length(plan.inserts)}
      unknown names: #{length(plan.unknown)}#{unknown}
    """
  end
end
