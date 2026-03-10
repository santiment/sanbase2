## MCP OAuth Implementation

### Overview

This backend exposes the existing MCP server behind an OAuth 2.0 authorization server implemented with `boruta`.

High-level flow:

1. MCP client calls `/.well-known/oauth-protected-resource`
2. MCP client discovers `/.well-known/oauth-authorization-server`
3. MCP client starts `GET /oauth/authorize?...`
4. If user is not logged in, backend redirects to the frontend login page with `?from=<full backend authorize url>`
5. After login, frontend redirects back to the backend authorize URL
6. Backend runs `preauthorize`, shows a consent screen, and on approval calls `authorize`
7. MCP client exchanges the code at `POST /oauth/token`
8. MCP requests use `Authorization: Bearer <jwt>`

### Main backend files

- `lib/sanbase_web/controllers/oauth_controller.ex`
  - OAuth metadata
  - protected resource discovery
  - authorize / consent flow
  - token endpoint
- `lib/sanbase_web/controllers/oauth_dev_login_controller.ex`
  - local-only dev login page
- `lib/sanbase/mcp/auth.ex`
  - validates boruta JWT access tokens for MCP requests
- `lib/sanbase/oauth/resource_owners.ex`
  - maps `Sanbase.Accounts.User` to boruta `ResourceOwner`
- `lib/sanbase_web/router.ex`
  - OAuth routes
- `priv/repo/seeds/mcp_oauth_client.exs`
  - creates the MCP OAuth client

### Routes

- `GET /.well-known/oauth-protected-resource`
- `GET /.well-known/oauth-authorization-server`
- `OPTIONS` for both of the above
- `GET /oauth/authorize`
- `POST /oauth/authorize`
- `POST /oauth/token`
- `OPTIONS /oauth/token`
- `GET/POST /oauth/dev_login` in `dev` and `test` only

### Frontend requirements

The frontend does not need to implement OAuth itself.

It only needs to support:

1. `GET /login?from=<full backend authorize url>`
2. After any successful login method, if `from` is present, redirect the browser to that URL

This must work for:

- Google / social login
- magic link login
- wallet / wallet connect login

`from` must allow trusted backend URLs such as `https://api.santiment.net/oauth/authorize?...`.

### Key decisions and why

#### 1. Use `boruta` instead of custom OAuth code

Why:

- PKCE support
- JWT access tokens
- standard OAuth flows
- less custom security-sensitive code to maintain

Tradeoff:

- heavier dependency
- more boruta-specific schema/config coupling

#### 2. Use JWT access tokens for MCP

Why:

- no database lookup per MCP request
- token validation is standard and fast

Tradeoff:

- access token revocation is not immediate; expiry is the main control

#### 3. Keep login in the frontend, not in Phoenix

Why:

- existing app already supports all login methods there
- avoids duplicating login UX and business rules

Tradeoff:

- frontend must support the `from` redirect contract

#### 4. Add explicit consent before code issuance

Why:

- safer and closer to expected OAuth behavior
- avoids silent authorization

Tradeoff:

- one extra screen in the flow

#### 5. Keep a dev-only local login screen

Why:

- easy local testing without frontend dependency

Tradeoff:

- separate dev-only path to maintain

### Production deployment

Before deploy:

1. Run boruta migrations

```bash
mix ecto.migrate
```

2. Create the MCP OAuth client

```bash
mix run priv/repo/seeds/mcp_oauth_client.exs
```

3. Store the generated client credentials somewhere safe
   - `client_id`
   - `client_secret`

4. Make sure frontend `/login` supports `?from=...`

5. Deploy frontend and backend together if the `from` handling is new

6. Verify the public backend URL is correct for OAuth metadata and redirects

### Manual test checklist

#### Local dev

1. Start backend
2. Open MCP Inspector or Claude Code
3. Point it to `http://localhost:4000/mcp`
4. Start OAuth flow
5. In dev, backend should redirect to `/oauth/dev_login`
6. Log in with an existing user email
7. Consent screen should appear
8. Approve
9. Token exchange should succeed
10. MCP call should succeed with bearer token

#### Frontend-integrated flow

1. Start OAuth flow against backend
2. Confirm backend redirects to `frontend/login?from=<encoded authorize url>`
3. Complete login in frontend
4. Confirm frontend redirects back to backend authorize URL
5. Confirm consent screen appears
6. Approve
7. Confirm token exchange succeeds
8. Confirm MCP request succeeds

### Review notes

These should be reviewed before relying on the flow in production:

1. `config/config.exs` currently sets:

```elixir
config :boruta, Boruta.Oauth,
  repo: Sanbase.Repo,
  issuer: "http://localhost:4000",
  contexts: [
    resource_owners: Sanbase.OAuth.ResourceOwners
  ]
```

This is fine for local development, but production needs the real issuer URL. This should likely move to runtime / environment-specific config.

2. `priv/repo/seeds/mcp_oauth_client.exs` currently prints only the created client id, not the secret. If the client is confidential and the secret is needed by tooling, developers need a reliable way to retrieve or re-seed it.

3. Dynamic client registration is not wired by our routes right now. If MCP Inspector or future clients should work without manually supplied credentials, this needs to be added explicitly.

4. CORS is currently permissive on OAuth discovery/token endpoints. That is acceptable for now, but should be reviewed before public rollout.
