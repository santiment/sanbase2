defmodule Sanbase.Accounts.Activity do
  use Ecto.Schema

  @type t :: %__MODULE__{
          id: non_neg_integer(),
          entity_id: non_neg_integer(),
          entity_type: String.t(),
          entity_details: Map.t(),
          activity_type: String.t()
        }

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Accounts.User

  schema "user_usage_activities" do
    field(:entity_id, :integer)
    field(:entity_type, :string)
    field(:entity_details, :map)
    field(:activity_type, :string)

    belongs_to(:user, User)

    timestamps()
  end

  @doc ~s"""

  """
  @spec store_user_activity(non_neg_integer(), Map.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def store_user_activity(user_id, args) do
    args = Map.put(args, :user_id, user_id)

    %__MODULE__{}
    |> cast(args, [:entity_id, :entity_type, :entity_details, :activity_type, :user_id])
    |> Sanbase.Repo.insert()
  end

  @doc ~s"""
  Return the most used entities of the given type for the user.
  The usage rank is based on the number of times the entity was used/viewed. More recent
  views contributred more to the score compared to old usage.

  In the future, the activity type can be weighted differently - 1 for view, 5 for like, etc.
  """
  @spec get_user_most_used(non_neg_integer(), String.t() | list(String.t()), Keyword.t()) ::
          {:ok, list(t())}
  def get_user_most_used(user_id, entity_type_or_types, opts) do
    {limit, offset} = Sanbase.Utils.Transform.opts_to_limit_offset(opts)
    entity_types = List.wrap(entity_type_or_types)

    from(
      row in __MODULE__,
      where: row.entity_type in ^entity_types and row.user_id == ^user_id,
      group_by: [row.entity_type, row.entity_id],
      select: %{entity_type: row.entity_type, entity_id: row.entity_id},
      order_by: [
        desc:
          fragment("""
          3 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '1 day' THEN 1 ELSE NULL END) +
          1.5 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '7 days' AND inserted_at < now() - INTERVAL '1 day' THEN 1 ELSE NULL END) +
          0.7 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '60 days' AND inserted_at < now() - INTERVAL '7 day' THEN 1 ELSE NULL END) +
          0.3 * COUNT(CASE WHEN inserted_at >= now() - INTERVAL '90 days' AND inserted_at < now() - INTERVAL '60 days' THEN 1 ELSE NULL END)
          """)
      ],
      offset: ^offset,
      limit: ^limit
    )
    |> Sanbase.Repo.all()
  end
end
