defmodule SanbaseWeb.Guardian do
  use Guardian, otp_app: :sanbase

  alias Sanbase.Auth.User
  alias Sanbase.Repo

  def subject_for_token(%User{id: id}, _claims) do
    {:ok, to_string(id)}
  end

  def resource_from_claims(%{"sub" => id}) do
    {:ok, Repo.get(User, id)}
  end

  def resource_from_claims(_claims) do
    {:error, :no_user_found}
  end

  def get_config(key) do
    Application.get_env(:sanbase, SanbaseWeb.Endpoint)
    |> Keyword.fetch!(key)
  end
end
