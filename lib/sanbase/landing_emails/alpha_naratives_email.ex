defmodule Sanbase.LandingEmails.AlphaNaratives do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo

  @mailjet_alpha_naratives :alpha_naratives_emails
  @alpha_naratives_welcome_template "alpha-naratives-welcome"

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
        Sanbase.Email.MailjetApi.client().subscribe(@mailjet_alpha_naratives, email)
        Sanbase.TemplateMailer.send(email, @alpha_naratives_welcome_template, %{})
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
