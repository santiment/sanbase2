defmodule Sanbase.LandingEmails.AlphaNaratives do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Email.MailjetApi

  @mailjet_alpha_naratives :alpha_naratives_emails

  schema "alpha_naratives_emails" do
    field(:email, :string)
    timestamps()
  end

  @doc false
  def changeset(email_struct, params \\ %{}) do
    email_struct
    |> cast(params, [:email])
    |> validate_required([:email])
    |> unique_constraint(:email, message: "Email is already added")
  end

  def create(email) do
    email = String.downcase(email)

    %__MODULE__{}
    |> changeset(%{email: email})
    |> Repo.insert()
    |> case do
      {:ok, result} ->
        MailjetApi.subscribe(@mailjet_alpha_naratives, email)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
