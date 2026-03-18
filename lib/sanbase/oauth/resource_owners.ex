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

  @impl Boruta.Oauth.ResourceOwners
  def authorized_scopes(%ResourceOwner{}) do
    # Return a broad set of scopes so that any scope requested by MCP clients
    # (Claude Desktop, Claude Code, etc.) is accepted. The actual access control
    # is enforced at the MCP tool level, not via OAuth scopes.
    ~w(openid profile email offline_access read write mcp)
    |> Enum.map(fn name -> %Boruta.Oauth.Scope{name: name} end)
  end

  @impl Boruta.Oauth.ResourceOwners
  def claims(_resource_owner, _scope), do: %{}
end
