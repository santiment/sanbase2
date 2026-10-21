defmodule Sanbase.Billing.BusinessClients.LogEntry do
  @moduledoc ~s"""
  Something a person noticed or did about a business client: a complaint, a payment
  issue, a retention action.

  The type is a plain string from the editable list in
  `Sanbase.Billing.BusinessClients.Settings`, so renaming or adding a type is a settings
  change. An open entry's severity drives the client's manual status until it is
  resolved.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @severities ~w(none at_risk high_risk)

  schema "business_client_log_entries" do
    field(:type, :string)
    field(:severity, :string, default: "none")
    field(:note, :string)
    field(:resolved_at, :utc_datetime)

    belongs_to(:user, Sanbase.Accounts.User)
    belongs_to(:author, Sanbase.Accounts.User)
    belongs_to(:resolved_by, Sanbase.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @spec severities() :: [String.t()]
  def severities, do: @severities

  @doc ~s"""
  A changeset for a new entry. `user_id` and `author_id` are set by the caller, not
  cast from form params.
  """
  def create_changeset(entry, attrs, settings) do
    entry
    |> cast(attrs, [:type, :severity, :note])
    |> validate_required([:type, :user_id, :author_id])
    |> validate_inclusion(:type, settings.issue_types)
    |> validate_inclusion(:severity, @severities)
    |> clear_severity_for(settings.types_without_severity)
    |> foreign_key_constraint(:user_id)
  end

  def resolve_changeset(entry, resolved_by_id) do
    change(entry,
      resolved_at: DateTime.utc_now() |> DateTime.truncate(:second),
      resolved_by_id: resolved_by_id
    )
  end

  defp clear_severity_for(changeset, types_without_severity) do
    if get_field(changeset, :type) in types_without_severity do
      put_change(changeset, :severity, "none")
    else
      changeset
    end
  end
end
