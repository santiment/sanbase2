defmodule Sanbase.Email.ListConsent do
  @moduledoc """
  Append-only record of a user subscribing to or unsubscribing from a
  consent-based email list (see `Sanbase.Email.Lists`). Stores when and where
  the choice was made, as evidence of the consent.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  alias Sanbase.Repo

  @sources ~w(signup_dialog privacy_page settings_toggle website_form mailjet_unsubscribe)a

  schema "email_list_consents" do
    belongs_to(:user, Sanbase.Accounts.User)

    field(:list, Ecto.Enum, values: [:newsletter])
    field(:subscribed, :boolean)
    field(:source, Ecto.Enum, values: @sources)

    timestamps(updated_at: false)
  end

  @type source ::
          :signup_dialog
          | :privacy_page
          | :settings_toggle
          | :website_form
          | :mailjet_unsubscribe

  @doc "Returns the allowed consent sources."
  @spec sources() :: [source()]
  def sources(), do: @sources

  @spec create(non_neg_integer(), atom(), boolean(), source()) ::
          {:ok, %__MODULE__{}} | {:error, Ecto.Changeset.t()}
  def create(user_id, list, subscribed, source) do
    %__MODULE__{}
    |> cast(%{user_id: user_id, list: list, subscribed: subscribed, source: source}, [
      :user_id,
      :list,
      :subscribed,
      :source
    ])
    |> validate_required([:user_id, :list, :subscribed, :source])
    |> foreign_key_constraint(:user_id)
    |> Repo.insert()
  end

  @doc "Returns the consent records of the user for the list, oldest first."
  @spec history(non_neg_integer(), atom()) :: [%__MODULE__{}]
  def history(user_id, list) do
    from(c in __MODULE__,
      where: c.user_id == ^user_id and c.list == ^list,
      order_by: [asc: c.inserted_at, asc: c.id]
    )
    |> Repo.all()
  end
end
