defmodule Sanbase.OAuth.ResourceOwners do
  @behaviour Boruta.Oauth.ResourceOwners

  alias Boruta.Oauth.ResourceOwner
  alias Sanbase.Accounts.User
  alias Sanbase.Repo

  @impl Boruta.Oauth.ResourceOwners
  def get_by(username: username) do
    case Repo.get_by(User, email: username) do
      %User{id: id, email: email} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: email}}

      nil ->
        {:error, "User not found."}
    end
  end

  def get_by(sub: sub) do
    case Repo.get_by(User, id: sub) do
      %User{id: id, email: email} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: email}}

      nil ->
        {:error, "User not found."}
    end
  end

  @impl Boruta.Oauth.ResourceOwners
  def check_password(_resource_owner, _password) do
    {:error, "Password grant not supported."}
  end

  @base_scopes ~w(openid profile email offline_access read write mcp)
  @team_scopes ~w(mcp:knowledge mcp:dev)

  @impl Boruta.Oauth.ResourceOwners
  def authorized_scopes(%ResourceOwner{username: email}) do
    # Return a broad set of base scopes so any scope requested by public MCP
    # clients is accepted, and grant team-only MCP resource scopes only to
    # `@santiment.net` accounts.
    scopes =
      if Sanbase.MCP.Knowledge.Access.team_email?(email),
        do: @base_scopes ++ @team_scopes,
        else: @base_scopes

    Enum.map(scopes, fn name -> %Boruta.Oauth.Scope{name: name} end)
  end

  @impl Boruta.Oauth.ResourceOwners
  def claims(_resource_owner, _scope), do: %{}
end
