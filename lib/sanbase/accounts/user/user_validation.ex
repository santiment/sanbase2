defmodule Sanbase.Accounts.User.Validation do
  alias Sanbase.Accounts.User

  def normalize_user_identificator(changeset, _field, nil), do: changeset

  def normalize_user_identificator(changeset, field, value) do
    Ecto.Changeset.put_change(changeset, field, normalize_user_identificator(field, value))
  end

  def normalize_user_identificator(:username, value) do
    value
    |> String.trim()
  end

  def normalize_user_identificator(_field, value) do
    value
    |> String.downcase()
    |> String.trim()
  end

  def validate_name_change(:name, name) do
    case User.Name.valid_name?(name) do
      true -> []
      {:error, error} -> [name: error]
    end
  end

  def validate_username_change(:username, username) do
    case User.Name.valid_username?(username) do
      true -> []
      {:error, error} -> [username: error]
    end
  end

  def validate_email_candidate_change(:email_candidate, email_candidate) do
    if Sanbase.Repo.get_by(User, email: email_candidate) do
      [email: "Email has already been taken"]
    else
      []
    end
  end

  def validate_url_change(:avatar_url, url) do
    case Sanbase.Validation.valid_url?(url) do
      :ok -> []
      {:error, msg} -> [avatar_url: msg]
    end
  end
end
