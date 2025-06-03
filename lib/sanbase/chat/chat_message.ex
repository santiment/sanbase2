defmodule Sanbase.Chat.ChatMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Chat.Chat

  @type role :: :user | :assistant
  @type context :: %{
          dashboard_id: String.t() | nil,
          asset: String.t() | nil,
          metrics: [String.t()] | nil
        }

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          content: String.t(),
          role: role(),
          context: context(),
          chat_id: Ecto.UUID.t(),
          chat: Chat.t() | Ecto.Association.NotLoaded.t(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @roles [:user, :assistant]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chat_messages" do
    field(:content, :string)
    field(:role, Ecto.Enum, values: @roles)
    field(:context, :map, default: %{})
    belongs_to(:chat, Chat)

    timestamps()
  end

  @required_fields [:content, :role, :chat_id]
  @optional_fields [:context]

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = chat_message, attrs \\ %{}) do
    chat_message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:content, min: 1)
    |> validate_inclusion(:role, @roles)
    |> validate_context()
    |> foreign_key_constraint(:chat_id)
  end

  @spec create_changeset(map()) :: Ecto.Changeset.t()
  def create_changeset(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
  end

  defp validate_context(changeset) do
    case get_change(changeset, :context) do
      nil ->
        changeset

      context when is_map(context) ->
        validate_context_fields(changeset, context)

      _ ->
        add_error(changeset, :context, "must be a map")
    end
  end

  defp validate_context_fields(changeset, context) do
    allowed_keys = ["dashboard_id", "asset", "metrics"]
    context_keys = Map.keys(context)

    invalid_keys = Enum.reject(context_keys, &(&1 in allowed_keys))

    case invalid_keys do
      [] ->
        validate_metrics_field(changeset, context)

      _ ->
        add_error(changeset, :context, "contains invalid keys: #{Enum.join(invalid_keys, ", ")}")
    end
  end

  defp validate_metrics_field(changeset, context) do
    case Map.get(context, "metrics") do
      nil ->
        changeset

      metrics when is_list(metrics) ->
        if Enum.all?(metrics, &is_binary/1) do
          changeset
        else
          add_error(changeset, :context, "metrics must be a list of strings")
        end

      _ ->
        add_error(changeset, :context, "metrics must be a list")
    end
  end

  def roles, do: @roles
end
