defmodule Sanbase.Dashboard.History do
  @moduledoc ~s"""
  Dashboard database schema and CRUD functions for working
  with it.

  This module is used for creating and updating dashboard fields.
  It also provide functions for adding/updating/removing dashboard panels
  """

  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  import Sanbase.Utils.Transform, only: [opts_to_limit_offset: 1]

  alias Sanbase.Repo
  alias Sanbase.Dashboard

  @type t :: %__MODULE__{
          # Inherited from Dashboard.Schmea
          name: String.t(),
          description: String.t(),
          is_public: boolean(),
          panels: list(Dashboard.Panel.t()),
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t(),
          #
          dashboard_id: non_neg_integer(),
          id: non_neg_integer(),
          message: String.t()
        }

  @type dashboard_id :: non_neg_integer()

  schema "dashboards_history" do
    field(:name, :string)
    field(:description, :string)
    field(:is_public, :boolean, default: false)

    embeds_many(:panels, Dashboard.Panel, on_replace: :delete)

    belongs_to(:dashboard, Dashboard.Schema)

    field(:message, :string)
    field(:hash, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = history, attrs) do
    history
    |> cast(attrs, [:name, :description, :is_public, :message, :dashboard_id, :hash])
    |> put_embed(:panels, attrs.panels)
  end

  def commit(%Dashboard.Schema{} = dashboard, message) do
    fields =
      dashboard
      |> Map.from_struct()
      |> Map.delete(:id)
      |> Map.put(:dashboard_id, dashboard.id)
      |> Map.put(:message, message)
      |> Map.put(:hash, generate_hash(dashboard, message))

    %__MODULE__{}
    |> changeset(fields)
    |> Repo.insert()
  end

  def get_history(dashboard_id, hash) do
    query =
      from(dh in __MODULE__,
        where: dh.dashboard_id == ^dashboard_id and dh.hash == ^hash,
        # Order by dt and not inserted_at as there could be records with the
        # same inserted_at, especially in tests
        order_by: [desc: dh.id]
      )

    case Repo.one(query) do
      nil -> {:error, "Dashboard History does not exist"}
      %__MODULE__{} = dh -> {:ok, dh}
    end
  end

  def get_history_list(dashboard_id, opts) do
    {limit, offset} = opts_to_limit_offset(opts)

    query =
      from(dh in __MODULE__,
        where: dh.dashboard_id == ^dashboard_id,
        order_by: [desc: dh.inserted_at],
        limit: ^limit,
        offset: ^offset
      )

    {:ok, Repo.all(query)}
  end

  defp generate_hash(dashboard, message) do
    binary_data = {dashboard, message, DateTime.utc_now()} |> :erlang.term_to_binary()

    :crypto.hash(:sha256, binary_data)
    |> Base.encode16(case: :lower)
    |> :erlang.binary_part(0, 40)
  end
end
