defmodule Sanbase.LandingEmails.SanrEmail do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Repo

  @mailjet_sanr_list :sanr_network_emails
  @sanr_network_welcome_template "sanr-network-welcome"

  schema "sanr_emails" do
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
        Sanbase.Email.MailjetApi.client().subscribe(@mailjet_sanr_list, email)
        Sanbase.TemplateMailer.send(email, @sanr_network_welcome_template, %{})
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
