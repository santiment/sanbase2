defmodule Sanbase.Email.NewsletterToken do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo

  @email_token_length 64
  # Email verification links will be valid 24 hours
  @login_email_valid_minutes 24 * 60

  schema "newsletter_tokens" do
    field(:email, :string)
    field(:email_token_generated_at, :utc_datetime)
    field(:email_token_validated_at, :utc_datetime)
    field(:token, :string)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(newsletter_token, attrs) do
    newsletter_token
    |> cast(attrs, [:token, :email, :email_token_generated_at, :email_token_validated_at])
    |> validate_required([:token, :email, :email_token_generated_at, :email_token_validated_at])
    |> unique_constraint(:email, name: :email_token_uk)
  end

  def get_by(email, token) do
    Repo.get_by(__MODULE__, email: email, token: token)
  end

  def create_email_token(email) do
    %__MODULE__{}
    |> change(
      email: email,
      token: generate_email_token(),
      email_token_generated_at: DateTime.utc_now() |> DateTime.truncate(:second),
      email_token_validated_at: nil
    )
    |> Repo.insert()
  end

  def mark_email_token_as_validated(newsletter_token) do
    newsletter_token
    |> change(email_token_validated_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def verify_token(email, token) do
    get_by(email, token)
    |> check_and_mark_valid_token()
  end

  def send_email(%__MODULE__{email: email, token: token}) do
    link = verify_url(token, email, "weekly_digest")

    Sanbase.Email.Template.verification_email_template()
    |> Sanbase.MandrillApi.send(email, %{VERIFY_LINK: link})
  end

  def subscribe_to_newsletter(email) do
    Sanbase.Email.MailchimpApi.add_email_to_mailchimp(email)
  end

  # helpers
  defp check_and_mark_valid_token(nil), do: {:error, :invalid_token}

  defp check_and_mark_valid_token(
         %__MODULE__{
           email_token_generated_at: email_token_generated_at,
           email_token_validated_at: email_token_validated_at
         } = newsletter_token
       ) do
    if is_nil(email_token_validated_at) &&
         Timex.diff(Timex.now(), email_token_generated_at, :minutes) <
           @login_email_valid_minutes do
      mark_email_token_as_validated(newsletter_token)
    else
      {:error, :expired_token}
    end
  end

  defp check_and_mark_valid_token(_), do: {:error, :unknown}

  defp verify_url(token, email, type) do
    SanbaseWeb.Endpoint.frontend_url() <>
      "/subscribe_email?" <>
      URI.encode_query(token: token, email: email, type: type)
  end

  defp generate_email_token do
    :crypto.strong_rand_bytes(@email_token_length) |> Base.url_encode64()
  end
end
