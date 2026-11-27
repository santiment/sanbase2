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

  @impl Boruta.Oauth.ResourceOwners
  def authorized_scopes(%ResourceOwner{sub: sub}) do
    # A broad set of base scopes so any scope requested by public MCP clients is
    # accepted. A team MCP scope is granted only to users allowed to use that MCP.
    # The team scopes must never be public Boruta scopes, because Boruta also
    # grants every public scope to clients without their own scope list.
    user = user_by_sub(sub)

    team_scopes =
      for {scope, access} <- [
            {"mcp:knowledge", Sanbase.MCP.Knowledge.Access},
            {"mcp:dev", Sanbase.MCP.Dev.Access}
          ],
          access.allowed?(user),
          do: scope

    Enum.map(@base_scopes ++ team_scopes, fn name -> %Boruta.Oauth.Scope{name: name} end)
  end

  defp user_by_sub(sub) do
    case Integer.parse(to_string(sub)) do
      {user_id, ""} -> Repo.get(User, user_id)
      _ -> nil
    end
  end

  @impl Boruta.Oauth.ResourceOwners
  def claims(_resource_owner, _scope), do: %{}
end
