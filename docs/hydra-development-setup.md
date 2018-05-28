## Clone hydra and checkout:

```
$ git clone https://github.com/ory/hydra.git
$ cd hydra
$ git checkout tags/v0.10.10.git
```

## Remove `consent-app` image, change the consent url to `Sanbase` local dev url:

```diff
diff --git a/docker-compose.yml b/docker-compose.yml
index 0ee789c..6418122 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -38,13 +38,12 @@ services:
       - hydravolume:/root
     ports:
       - "4444:4444"
-      - "4445:4445"
     command:
       host --dangerous-auto-logon --dangerous-force-http --disable-telemetry
     environment:
       - LOG_LEVEL=debug
       - ISSUER=http://localhost:4444
-      - CONSENT_URL=http://localhost:3000/consent
+      - CONSENT_URL=http://localhost:4000/login
       - DATABASE_URL=postgres://hydra:secret@postgresd:5432/hydra?sslmode=disable
 #     Uncomment the following line to use mysql instead.
 #      - DATABASE_URL=mysql://root:secret@tcp(mysqld:3306)/mysql?parseTime=true
@@ -52,19 +51,6 @@ services:
       - SYSTEM_SECRET=youReallyNeedToChangeThis
     restart: unless-stopped

-  consent:
-    environment:
-      - HYDRA_URL=http://hydra:4444
-      - HYDRA_CLIENT_ID=admin
-      - HYDRA_CLIENT_SECRET=demo-password
-      - NODE_TLS_REJECT_UNAUTHORIZED=0
-    image: oryd/hydra-consent-app-express:v0.10.0-alpha.7
-    links:
-      - hydra
-    ports:
-      - "3000:3000"
-    restart: unless-stopped
-
   postgresd:
     image: postgres:9.6
     ports:
```

## Start the containers:

```
$ docker-compose -p hydra up --build -d
```
After running this - you should have these 2 containers running `docker ps`:
```
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                    NAMES
7ca1aabe6fef        hydra_hydra         "hydra host --danger…"   3 hours ago         Up 3 hours          0.0.0.0:4444->4444/tcp   hydra_hydra_1
d578d5ea5bb0        postgres:9.6        "docker-entrypoint.s…"   2 weeks ago         Up 7 days           0.0.0.0:5432->5432/tcp   hydra_postgresd_1
```

## SSH into hydra conatiner:
```
$ docker exec -i -t hydra_hydra_1 /bin/sh
```

## Create `grafana` and `consent-app` clients
```bash
$ hydra clients create --skip-tls-verify --id grafana --secret grafana-secret -g authorization_code,refresh_token,client_credentials -r token,code,id_token --allowed-scopes openid,offline,hydra.clients,hydra.consent --callbacks http://localhost:5555/login/generic_oauth
```

```bash
hydra clients create --skip-tls-verify --id consent-app --secret consent-secret -g client_credentials -r token --allowed-scopes hydra.consent
```
* scopes: what scopes are allowed for this client
* callbacks: http://localhost:5555/login/generic_oauth - redirect url - in this case local `grafana`

## Check the created client
```
$ hydra clients get grafana
```
```javascript
{
	"grant_types": [
		"authorization_code",
		"refresh_token",
		"client_credentials"
	],
	"id": "grafana",
	"redirect_uris": [
		"http://localhost:5555/login/generic_oauth"
	],
	"response_types": [
		"token",
		"code",
		"id_token"
	],
	"scope": "openid offline hydra.clients hydra.consent"
}
```

## Create policy for grafana and conent-app clients
```bash
$ hydra policies create --skip-tls-verify --actions get,accept,reject --description "Allow consent-app to manage OAuth2 consent requests." --allow --id consent-app-policy --resources "rn:hydra:oauth2:consent:requests:<.*>" --subjects grafana
```

```bash
hydra policies create --skip-tls-verify --actions get,accept,reject --description "Allow consent-app to manage OAuth2 consent requests." --allow --id con
sent-app-policy --resources "rn:hydra:oauth2:consent:requests:<.*>" --subjects consent-app
```

## Check the created policies
```bash
$ hydra policies get consent-app-policy
```

```javascript
{
	"actions": [
		"reject",
		"get",
		"accept"
	],
	"description": "Allow consent-app to manage OAuth2 consent requests.",
	"effect": "allow",
	"id": "consent-app-policy",
	"resources": [
		"rn:hydra:oauth2:consent:requests:\u003c.*\u003e"
	],
	"subjects": [
		"grafana",
		"consent-app"
	]
}
```

References:
1. Hydra 5 min tutorial: https://www.ory.sh/docs/guides/latest/1-hydra/0-tutorial/0-readme
2. Hydra API: `https://www.ory.sh/docs/api/hydra/`
