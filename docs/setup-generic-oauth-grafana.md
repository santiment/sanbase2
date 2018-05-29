## Setup the hydra oauth2 server and create client:
(hydra-development-setup.md)


## Configure Sanbase `.env`

```
HYDRA_BASE_URL=http://localhost:4444
HYDRA_TOKEN_URI=/oauth2/token
HYDRA_CONSENT_URI=/oauth2/consent/requests
HYDRA_CLIENT_ID=consent-app
HYDRA_CLIENT_SECRET=consent-secret
```

## Configure grafana generic oauth

```
[auth.generic_oauth]
enabled = true
name = Sanbase
allow_sign_up = true
client_id = grafana
client_secret = grafana-secret
scopes = "openid offline hydra.clients"
auth_url = http://localhost:4444/oauth2/auth
token_url = http://localhost:4444/oauth2/token
api_url = http://localhost:4444/userinfo
;team_ids =
;allowed_organizations =
```
