defmodule Sanbase.Metric.Category.Scripts.SeedSocialCategoryTest do
  use Sanbase.DataCase, async: false

  import ExUnit.CaptureIO, only: [with_io: 1]

  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Category.Scripts.SeedSocialCategory
  alias Sanbase.Repo

  test "plan writes nothing" do
    plan = quietly(&SeedSocialCategory.plan/0)

    assert plan.category == nil
    assert plan.inserts != []
    assert Repo.get_by(MetricCategory, name: "Social") == nil
    assert Repo.aggregate(MetricCategoryMapping, :count) == 0
  end

  test "creates the category and maps registry and module metrics, ungrouped" do
    quietly(&SeedSocialCategory.apply!/0)

    category = Repo.get_by!(MetricCategory, name: "Social")
    mappings = Repo.all(from(m in MetricCategoryMapping, where: m.category_id == ^category.id))

    assert Enum.all?(mappings, &is_nil(&1.group_id))

    {:ok, social_volume_total} = Sanbase.Metric.Registry.by_name("social_volume_total")
    assert Enum.any?(mappings, &(&1.metric_registry_id == social_volume_total.id))

    for {module, metric} <- [
          {"Sanbase.SocialData.MetricAdapter", "nft_social_volume"},
          {"Sanbase.SocialData.MetricAdapter", "social_active_users"},
          {"Sanbase.Twitter.MetricAdapter", "twitter_followers"}
        ] do
      assert Enum.any?(mappings, &(&1.module == module and &1.metric == metric)), metric
    end

    # The display order continues from the rows that are already there
    orders = mappings |> Enum.map(& &1.display_order) |> Enum.sort()
    assert orders == Enum.to_list(1..length(mappings))
  end

  test "a second run changes nothing" do
    quietly(&SeedSocialCategory.apply!/0)
    count = Repo.aggregate(MetricCategoryMapping, :count)

    plan = quietly(&SeedSocialCategory.plan/0)
    assert plan.inserts == []
    assert plan.category.name == "Social"

    quietly(&SeedSocialCategory.apply!/0)
    assert Repo.aggregate(MetricCategoryMapping, :count) == count
  end

  test "a metric mapped in another category still gets a row in Social" do
    {:ok, market} = MetricCategory.create(%{name: "Market", display_order: 1})
    {:ok, social_volume_total} = Sanbase.Metric.Registry.by_name("social_volume_total")

    {:ok, _} =
      MetricCategoryMapping.create(%{
        metric_registry_id: social_volume_total.id,
        category_id: market.id
      })

    quietly(&SeedSocialCategory.apply!/0)

    social = Repo.get_by!(MetricCategory, name: "Social")

    assert Repo.exists?(
             from(m in MetricCategoryMapping,
               where:
                 m.category_id == ^social.id and m.metric_registry_id == ^social_volume_total.id
             )
           )
  end

  test "the names that are neither registry nor adapter metrics are reported, not mapped" do
    plan = quietly(&SeedSocialCategory.plan/0)

    known = Enum.map(plan.inserts, &elem(&1, 0))
    assert Enum.sort(known ++ plan.unknown) == Enum.sort(SeedSocialCategory.metrics())
  end

  test "the taxonomy importer can then sort the seeded metrics into groups" do
    quietly(&SeedSocialCategory.apply!/0)

    [plan] = quietly(fn -> Sanbase.Metric.Category.TaxonomyImporter.plan(["social"]) end)

    refute Map.has_key?(plan, :error)
    assert plan.inserts != []
    assert plan.ungrouped_deletions != []
  end

  defp quietly(fun) do
    {result, _output} = with_io(fun)
    result
  end
end
