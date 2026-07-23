defmodule Sanbase.Metric.TagTest do
  use Sanbase.DataCase, async: false

  import Sanbase.MetricRegistryHelpers, only: [create_registry_metric: 1]

  alias Sanbase.Metric.Tag

  describe "tag CRUD" do
    test "create, get, update and delete a tag" do
      assert {:ok, tag} = Tag.create_tag(%{name: "my_tag", description: "desc"})
      assert tag.name == "my_tag"
      assert tag.description == "desc"

      assert {:ok, ^tag} = Tag.get_tag(tag.id)
      assert %{name: "my_tag"} = Tag.get_tag_by_name("my_tag")

      assert {:ok, updated} = Tag.update_tag(tag, %{description: "new desc"})
      assert updated.description == "new desc"

      assert {:ok, _} = Tag.delete_tag(updated)
      assert {:error, _} = Tag.get_tag(tag.id)
    end

    test "tag name must be unique" do
      assert {:ok, _} = Tag.create_tag(%{name: "dup_tag"})
      assert {:error, changeset} = Tag.create_tag(%{name: "dup_tag"})
      assert "has already been taken" in errors_on(changeset).name
    end

    test "name is required" do
      assert {:error, changeset} = Tag.create_tag(%{description: "no name"})
      assert "can't be blank" in errors_on(changeset).name
    end

    test "seeded vocabulary tags exist" do
      names = Tag.list_tags() |> Enum.map(& &1.name)

      for expected <- ~w(basic development_data market_data social_data onchain_data) do
        assert expected in names
      end
    end
  end

  describe "mapping constraints" do
    setup do
      {:ok, tag} = Tag.create_tag(%{name: "constraint_tag"})
      %{tag: tag}
    end

    test "rejects a mapping with neither identifier", %{tag: tag} do
      assert {:error, changeset} = Tag.create_mapping(%{tag_id: tag.id})
      refute changeset.valid?
    end

    test "rejects a mapping with both identifiers", %{tag: tag} do
      registry = create_registry_metric("both_ids_metric")

      assert {:error, changeset} =
               Tag.create_mapping(%{
                 tag_id: tag.id,
                 metric_registry_id: registry.id,
                 module: "Some.Module",
                 metric: "some_metric"
               })

      refute changeset.valid?
    end

    test "accepts a registry-backed mapping", %{tag: tag} do
      registry = create_registry_metric("registry_backed_metric")

      assert {:ok, mapping} =
               Tag.create_mapping(%{tag_id: tag.id, metric_registry_id: registry.id})

      assert mapping.metric_registry_id == registry.id
    end

    test "accepts a module/metric mapping", %{tag: tag} do
      assert {:ok, mapping} =
               Tag.create_mapping(%{
                 tag_id: tag.id,
                 module: "Sanbase.Price.MetricAdapter",
                 metric: "price_usd"
               })

      assert mapping.metric == "price_usd"
    end

    test "rejects the same (registry metric, tag) pair twice", %{tag: tag} do
      registry = create_registry_metric("dup_registry_metric")

      assert {:ok, _} = Tag.create_mapping(%{tag_id: tag.id, metric_registry_id: registry.id})

      assert {:error, changeset} =
               Tag.create_mapping(%{tag_id: tag.id, metric_registry_id: registry.id})

      refute changeset.valid?
    end

    test "rejects the same (module/metric, tag) pair twice", %{tag: tag} do
      attrs = %{tag_id: tag.id, module: "Sanbase.Price.MetricAdapter", metric: "price_usd"}

      assert {:ok, _} = Tag.create_mapping(attrs)
      assert {:error, changeset} = Tag.create_mapping(attrs)
      refute changeset.valid?
    end
  end

  describe "multiple tags per metric" do
    test "a single metric can carry more than one tag" do
      {:ok, tag_a} = Tag.create_tag(%{name: "multi_a"})
      {:ok, tag_b} = Tag.create_tag(%{name: "multi_b"})

      attrs_a = %{tag_id: tag_a.id, module: "Sanbase.Price.MetricAdapter", metric: "price_usd"}
      attrs_b = %{tag_id: tag_b.id, module: "Sanbase.Price.MetricAdapter", metric: "price_usd"}

      assert {:ok, _} = Tag.create_mapping(attrs_a)
      assert {:ok, _} = Tag.create_mapping(attrs_b)

      Tag.refresh_stored_terms()

      assert Enum.sort(Tag.tags_for_metric("price_usd")) == ["multi_a", "multi_b"]
    end
  end

  describe "refresh_stored_terms/0" do
    test "returns true" do
      assert Tag.refresh_stored_terms() == true
    end
  end
end
