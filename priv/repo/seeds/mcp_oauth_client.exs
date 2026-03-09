alias Boruta.Ecto.Admin.Clients

client_id = System.get_env("MCP_OAUTH_CLIENT_ID", Ecto.UUID.generate())
client_secret = System.get_env("MCP_OAUTH_CLIENT_SECRET", SecureRandom.hex(64))

case Sanbase.Repo.get(Boruta.Ecto.Client, client_id) do
  nil ->
    private_key = JOSE.JWK.generate_key({:rsa, 2048, 65_537})
    public_key = JOSE.JWK.to_public(private_key)
    {_type, public_pem} = JOSE.JWK.to_pem(public_key)
    {_type, private_pem} = JOSE.JWK.to_pem(private_key)

    {:ok, client} =
      Clients.create_client(%{
        id: client_id,
        secret: client_secret,
        name: "Sanbase MCP",
        access_token_ttl: 3600,
        authorization_code_ttl: 60,
        refresh_token_ttl: 30 * 86_400,
        redirect_uris: [
          "http://localhost:6274/oauth/callback",
          "http://localhost:6274/oauth/callback/debug",
          "https://claude.ai/api/mcp/auth_callback",
          "https://claude.com/api/mcp/auth_callback"
        ],
        supported_grant_types: ["authorization_code", "refresh_token"],
        pkce: true,
        public_refresh_token: true,
        confidential: false,
        token_endpoint_auth_methods: ["client_secret_post", "client_secret_basic"],
        public_key: public_pem,
        private_key: private_pem
      })

    IO.puts("Created MCP OAuth client:")
    IO.puts("  client_id:     #{client.id}")
    IO.puts("  client_secret: #{client_secret}")
    IO.puts("")
    IO.puts("Use these when connecting MCP Inspector or Claude Code.")

  existing ->
    IO.puts("MCP OAuth client already exists: #{existing.id}")
end
