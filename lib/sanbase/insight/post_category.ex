defmodule Sanbase.Insight.PostCategory do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Insight.{Post, Category}

  schema "insight_category_mapping" do
    belongs_to(:post, Post)
    belongs_to(:category, Category)
    field(:source, :string, default: "ai")

    timestamps()
  end

  def changeset(%__MODULE__{} = mapping, attrs \\ %{}) do
    mapping
    |> cast(attrs, [:post_id, :category_id, :source])
    |> validate_required([:post_id, :category_id, :source])
    |> validate_inclusion(:source, ["ai", "human"])
    |> unique_constraint([:post_id, :category_id])
  end

  def get_post_categories(post_id) do
    from(
      m in __MODULE__,
      where: m.post_id == ^post_id,
      join: c in Category,
      on: m.category_id == c.id,
      select: %{
        category_id: c.id,
        category_name: c.name,
        source: m.source
      }
    )
    |> Repo.all()
  end

  def get_categories_for_posts(post_ids) when is_list(post_ids) do
    from(
      m in __MODULE__,
      where: m.post_id in ^post_ids,
      join: c in Category,
      on: m.category_id == c.id,
      select: %{
        post_id: m.post_id,
        category_id: c.id,
        category_name: c.name,
        source: m.source
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.post_id)
  end

  def assign_categories(post_id, category_ids, source) when is_list(category_ids) do
    # Delete existing mappings for this post with the same source
    from(m in __MODULE__, where: m.post_id == ^post_id and m.source == ^source)
    |> Repo.delete_all()

    # Insert new mappings
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    mappings =
      Enum.map(category_ids, fn category_id ->
        %{
          post_id: post_id,
          category_id: category_id,
          source: source,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(__MODULE__, mappings)
    {:ok, mappings}
  end

  def override_with_human_categories(post_id, category_ids) do
    # Delete all AI-sourced categories for this post
    from(m in __MODULE__, where: m.post_id == ^post_id and m.source == "ai")
    |> Repo.delete_all()

    # Assign new categories as human-sourced
    assign_categories(post_id, category_ids, "human")
  end

  def has_human_categories?(post_id) do
    from(m in __MODULE__, where: m.post_id == ^post_id and m.source == "human", limit: 1)
    |> Repo.exists?()
  end

  def delete_ai_categories(post_id) do
    from(m in __MODULE__, where: m.post_id == ^post_id and m.source == "ai")
    |> Repo.delete_all()
  end
end
