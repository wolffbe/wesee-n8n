# wesee

Wesee automates the extraction and structuring of startups and their company properties from emails and their attachments sent to `deals@` or `info@` inboxes of venture capital (VC) firms into a Notion database, e.g. company names and descriptions.

>In the latest test conducted together with an emerging healthtech VC, **90 emails were analyzed for relevance** in accordance with the VC’s investment thesis. The contents of 23 remaining emails were structured in Notion across 18 properties **in 28 minutes and 4 seconds**.
>
>The extraction of **18 properties** from a relevant email and its attachments took an average of **one minute**. Assuming a real VC analyst would take five to ten minutes to extract the same amount of properties, this automation **accelerates the process by at least 400%**.
>

## Overview

The workflow is hosted in [N8n](https://github.com/n8n-io/),

- reads Outlook emails and their attachments **every hour**,
- classifies emails according to their relevance to the VC,
- extracts companies and their properties,
- saves them in a Notion database,
- and stores the pitch deck in OneDrive.

## Requirements

- N8n
- Docker
- Make
- Microsoft Entra (app registration, to authenticate against Outlook and OneDrive)
- Microsoft Outlook
- Microsoft OneDrive / Microsoft SharePoint
- OpenAI
- Notion

## Credentials

The following credentials are required in n8n to run the workflow:

- Microsoft Outlook OAuth2 API
- Microsoft OAuth2 API with a scope containing `Files.ReadWrite`, `Files.ReadWrite.All`, `Sites.ReadWrite.All` and `offline_access` 
- OpenAI
- Notion API

All of them need to be named `wesee`.

Both Microsoft credentials are backed by **one** Entra app registration and take the same client ID and the same certificate or secret — they are separate only because n8n splits the mailbox scopes from the file scopes. See [Microsoft Entra](#microsoft-entra) below.

## Setup

This setup was tested using [n8n in Docker](https://docs.n8n.io/hosting/installation/docker/). N8n can also be setup in the cloud. In that case, the workflows need to be imported manually.

### Notion

1. Setup the database in Notion (add [integration](https://www.notion.so/my-integrations), set the database connection in your database's page and identify the URL of the page via `share` in the top-right hand corner of the page)
2. Add database properties (i.e. table columns) with descriptions that specifically define each property. **Only properties with descriptions are processed OpenAI❗**

### Microsoft Entra

Outlook and OneDrive/SharePoint are reached with delegated Microsoft Graph permissions, so they need an app registration in [Microsoft Entra](https://entra.microsoft.com) → **App registrations**. One registration serves both Microsoft credentials in n8n.

**1. Register the app**

- **New registration**, name it e.g. `wesee`.
- Supported account types: **Accounts in this organizational directory only** for a company mailbox. Only choose a multi-tenant/personal option if you actually need it — see the endpoint note in step 5.
- Redirect URI, platform **Web**: `http://localhost:5678/rest/oauth2-credential/callback`

  It must match n8n's callback exactly. Entra permits plain `http` for `localhost` on the Web platform; an `http://127.0.0.1` URI is the public-client/native path and is not interchangeable here, because n8n authenticates as a confidential client.

**2. Copy the identifiers** from **Overview**: *Application (client) ID* and *Directory (tenant) ID*.

**3. Add a credential** under **Certificates & secrets**. Either works, but prefer a certificate:

- *Certificate* (recommended) — generate a self-signed keypair, upload only the public half, and keep the key locally:

  ```sh
  openssl req -x509 -newkey rsa:2048 -keyout wesee-key.pem -out wesee-cert.pem -days 730 -nodes -subj "/CN=wesee-n8n"
  ```

  Upload `wesee-cert.pem` on the **Certificates** tab. n8n signs a `private_key_jwt` assertion with the key instead of sending a shared secret. This is also the only option if your tenant blocks secrets — an app management policy with the `passwordAddition` restriction makes "New client secret" fail with *"Client secrets are blocked by a tenant-wide policy"*. That policy does not block the registration itself, only adding a password to it.

  On Git Bash for Windows, run `openssl` with `MSYS_NO_PATHCONV=1`, or the `-subj` value is rewritten into a Windows path and the certificate gets the wrong subject.

- *Client secret* — **Certificates & secrets** → *New client secret*, and copy the **Value** immediately; it is shown only once.

**4. Grant permissions** under **API permissions** → **Microsoft Graph** → **Delegated**. The registration needs the union of what both credentials use:

| Permission | Needed by |
| --- | --- |
| `Mail.ReadWrite` | reading the mailbox, marking mail read |
| `Files.ReadWrite.All` | storing attachments in OneDrive/SharePoint |
| `Sites.ReadWrite.All` | storing attachments on a SharePoint site |
| `offline_access` | refresh tokens, so n8n does not need reconnecting |
| `User.Read` | sign-in |

Grant admin consent if your tenant requires it. `Mail.Send` is not needed — wesee never sends mail.

**5. Fill in both n8n credentials** — `wesee` (Microsoft Outlook OAuth2 API) *and* `wesee` (Microsoft OAuth2 API) — with identical values:

- **Client ID**: the Application (client) ID
- **Authentication**: `Certificate`, then paste `wesee-key.pem` into *Private Key* and `wesee-cert.pem` into *Certificate* — each including its `-----BEGIN ...-----` and `-----END ...-----` lines. Omitting those lines leaves a value n8n cannot parse. For a secret instead, leave **Authentication** on `Client Secret` and paste the secret Value.
- **Authorization URL** and **Access Token URL**: for a single-tenant registration, replace `common` with your Directory (tenant) ID:

  ```
  https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize
  https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token
  ```

  n8n defaults to `/common`, which only works for registrations that allow personal Microsoft accounts. Leaving `/common` on a single-tenant app fails with `unauthorized_client: The client does not exist or is not enabled for consumers`.
- Leave the Outlook credential's **Custom Scopes** off; its scopes are set automatically.

Then press *Connect my account* on each and sign in with the `deals@`/`info@` mailbox. You consent twice, once per credential, because they request different scopes.

### N8n

Run these from PowerShell. From Git Bash, MSYS rewrites POSIX-looking arguments before `docker.exe` sees them, which turns `-v /c/…:/home/node/wesee` into a mount of `…wesee;C` at `\Program Files\Git\home\node\wesee`; export `MSYS_NO_PATHCONV=1` and `MSYS2_ARG_CONV_EXCL=*` if you must.

**1. Start n8n**

```powershell
docker volume create n8n_data
docker run -d --name n8n -p 127.0.0.1:5678:5678 `
  --sysctl net.ipv6.conf.all.disable_ipv6=1 `
  -e N8N_LISTEN_ADDRESS=0.0.0.0 `
  -e N8N_DIAGNOSTICS_ENABLED=false `
  -e N8N_VERSION_NOTIFICATIONS_ENABLED=false `
  -e N8N_TEMPLATES_ENABLED=false `
  -e N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=false `
  -v n8n_data:/home/node/.n8n `
  -v "${PWD}\wesee:/home/node/wesee" `
  n8nio/n8n:stable
```

It is ready when `docker logs n8n` prints "Editor is now accessible via". If `docker` fails with a pipe error, Docker Desktop's engine is still starting — wait and retry.

Three of those flags are load-bearing and should not be dropped:

| Flag | Why |
| --- | --- |
| `-p 127.0.0.1:5678:5678` | Publishing on all interfaces also creates an IPv6 binding. On Windows a `dllhost.exe` COM surrogate can take `[::1]:5678`, accept connections and forward nothing. Since `localhost` resolves to `::1` first and the hijacked socket *times out* rather than refusing, clients never fall back to IPv4 and `http://localhost:5678` appears dead. |
| `--sysctl net.ipv6.conf.all.disable_ipv6=1` | The container has no IPv6 route, but Docker's DNS can return only AAAA records for `login.microsoftonline.com`. The OAuth token exchange then dies with `connect ENETUNREACH …:443` *after* browser consent has already succeeded. `NODE_OPTIONS=--dns-result-order=ipv4first` is **not** enough — it only reorders `dns.lookup`. |
| `N8N_LISTEN_ADDRESS=0.0.0.0` | Required by the line above: n8n otherwise binds `::` and fails to start. |

`n8nio/n8n:stable` is deliberate — n8n 2.x renamed the `latest` channel, so bare `n8nio/n8n` resolves to a tag that may not exist.

**2. Create the owner account** at http://localhost:5678 and set up the four `wesee` credentials (see [Credentials](#credentials) and [Microsoft Entra](#microsoft-entra)).

**3. Import the workflows and publish them.** `wesee/` is bind-mounted, so the files are already inside the container:

```powershell
docker exec n8n n8n import:workflow --separate --input=/home/node/wesee/workflows
docker exec n8n n8n list:workflow | ForEach-Object { ($_ -split '\|')[0] } |
  ForEach-Object { docker exec n8n n8n publish:workflow --id=$_ }
docker restart n8n
```

**Publishing is not optional.** n8n 2.x replaced the Active toggle with publish/draft, `import:workflow` always lands workflows as **drafts**, and an Execute Workflow node calls the *published* version of its target. An unpublished sub-workflow fails with `Workflow is not active and cannot be executed`, reported against the *calling* node — so it reads as a problem in, say, `get database properties` when the real cause is that `get emails` is a draft. Publish every workflow after every import, not just the ones you changed, and restart afterwards: the CLI warns that publishing has no effect while n8n is running.

Do **not** use `make imwf` / `make im` with the bind mount. Their first step runs `rm -rf /home/node/wesee/workflows*` against the mounted host folder, deleting the workflow JSONs before importing them (recover with `git checkout -- wesee`).

**4. Configure and test.** Fill in `set workflow configuration` — at minimum `config.notion.url` and `config.thesis` (full list below) — then run with `config.cache.reset` set to `true`.

To debug a failing run, execute it in the foreground:

```powershell
docker exec n8n n8n execute --id <workflowId>
```

This prints every node result and the full error. The Executions list is not a reliable substitute: n8n does not persist node-level run data for manual executions, so a run can show no progress for minutes while working normally.

## Run

1. Set `config.cache.add` to `true`
2. Set `config.email.get.batch` to `25`
3. Set `config.email.get.read` to `unread`
4. Set `config.email.set.read` to `true`
5. (Optional) Set `config.notion.url` to a production database after adding the Notion connector to the page
6. (Optional) Set emails in Outlook inbox to `unread`
7. Set the `wesee` workflow to `active`

Note: The throttle `config.email.get.batch` should only be used in combination with setting `config.email.get.read` to `unread` and `config.email.set.read` to `true`❗

## Configuration

The following workflow properties are configurable in the node `set workflow configuration`:

| **Parameter**                          | **Description**                                                                                      | **Example Value**                                   |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| `config.blacklist.file.name.contains`  | Array of blacklisted file name contents                                                              | `["facebook", "twitter"]`                           |
| `config.blacklist.properties.contains` | Array of blacklisted property values                                                                 | `["VC company name", "VC executive", "VC address"]` |
| `config.cache.add`                     | Add emails to cache to avoid duplicate processing                                                    | `true` or `false`                                   |
| `config.cache.reset`                   | Reset duplication cache                                                                              | `true` or `false`                                   |
| `config.drive.name`                    | Name of the OneDrive or SharePoint drive                                                             | `Documents`                                         |
| `config.folder.name`                   | Name of the root folder for storing attachments                                                      | `wesee`                                             |
| `config.folder.path`                   | Path of the root folder in the drive                                                                 | `/sub/folder`                                       |
| `config.email.get.batch`               | Throttle amount of emails being processed in one workflow (`0` defaults to maximum amount of emails) | `12`                                                |
| `config.email.get.read`                | Get types of email                                                                                   | `read` OR `unread` OR `both`                        |
| `config.email.get.after`               | Get email after date                                                                                 | `2025-02-17T00:00:00Z`                              |
| `config.email.set.read`                | Set emails to read or unread after processing                                                        | `true` OR `false`                                   |
| `config.notion.url`                    | URL to page containing Notion database                                                               | `https://www.notion.so/VC/id`                       |
| `config.openai.model`                  | OpenAI model used for classification and property extraction                                         | `gpt-4o`                                            |
| `config.site.host`                     | Host URL of the SharePoint site (leave blank if using personal OneDrive)                             | `https://VC-my.sharepoint.com`                      |
| `config.site.name`                     | Name of the SharePoint site                                                                          | `VC company SharePoint`                             |
| `config.thesis`                        | VC thesis used in email classification                                                               | `Early-stage health tech in the US and Taiwan`      |

If `site` is not set, the workflow will try to find the configured drive in your personal OneDrive. If `drive` is not set, a default drive in your personal OneDrive will be used. If `path` is not set, the folder will be placed in the root of its drive.

`config.notion.url`, `config.thesis` and `config.blacklist.properties.contains` are deliberately empty in this repository — they identify a specific deployment. Fill them in after importing, and re-enter them after any later import, which overwrites the node with the committed values. Exporting with `make exwf` writes them back into `wesee.json`, so check the diff before committing.

## OpenAI

Classification and property extraction both use the OpenAI **Chat Completions** API, with one request per described Notion property (`temperature` 0). The model is taken from `config.openai.model` and defaults to `gpt-4o`.

Earlier versions used the OpenAI Assistants API, which OpenAI shut down on 26 August 2026. The workflows no longer create, reuse or delete assistants: `wesee - create assistant` only assembles the system prompt, the former `delete assistant` step is a no-op, and `wesee - utils` only clears the deduplication cache. Rate limits and gateway errors (429, 502, 503, timeouts) are routed into the existing wait-and-retry loop.

## Examples

The [`examples`](./examples) folder contains two fictional pitch decks with matching email bodies for testing the workflow end to end: **Vitera Health** (early-stage healthtech, raising EUR 450K) as the positive case that fits the default thesis, and **NeuralNex** (Series A enterprise AI, raising USD 15M) as the negative case that should be rejected on thesis fit. See [examples/README.md](./examples/README.md).

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `http://localhost:5678` hangs, `127.0.0.1` works | Published on all interfaces; see the `-p 127.0.0.1` row above |
| `connect ENETUNREACH …:443` after consent | Container resolved only AAAA records; see the sysctl row above |
| `Problem in node 'X'` where X looks fine | A sub-workflow it calls is an unpublished draft — publish all and restart |
| `Workflow is not active and cannot be executed` | Same as above |
| Execution sits at `running` with no progress | Either a permanent API error being retried, or simply unrecorded manual-run data — use `n8n execute` |
| `'config.…' expects a array but we got ''` | A typed config field left as a bare `=`; give it an explicit value |
| `invalid syntax` on a node whose JSON is valid | An embedded JSON literal contains `}}`, which closes the n8n expression early |
| Notion rows appear but are blank | The Notion write keys off each property's `type`; check `deal.properties` still carries it |
| `body failed validation … description.length ≤ 280` | Notion caps property descriptions at 280 characters |
| `Cannot change title to a different property type` | A title update must include its type key, `title: {}` |
| Columns appear in the wrong order | Notion's API cannot set column order — arrange them once in the UI; the workflow only adds missing columns |

## Importing and exporting workflows

A `Makefile` is available to handle importing and exporting workflows between the n8n Docker container and its host:

| **Command**    | **Description**                                                           |
| -------------- | ------------------------------------------------------------------------- |
| `make install` | Setup n8n Docker volume and create export folders                         |
| `make start`   | Start n8n in Docker locally                                               |
| `make startfg` | Start n8n in Docker locally with logging in foreground                    |
| `make stop`    | Stop n8n in Docker locally                                                |
| `make imwf`    | Import workflows from the host to n8n in Docker                           |
| `make imcr`    | Import credentials from the host to n8n in Docker                         |
| `make im`      | Import workflows and credentials from the host to n8n in Docker           |
| `make exwf`    | Export workflows from n8n in Docker to the host                           |
| `make excr`    | Export credentials from n8n in Docker to the host                         |
| `make excrd`   | Export decrypted credentials from n8n in Docker to the host               |
| `make ex`      | Export workflows and credentials from n8n in Docker to the host           |
| `make exd`     | Export workflows and decrypted credentials from n8n in Docker to the host |
| `make remove`  | Remove n8n Docker containers and volume |

Exported credentials are saved in the `credentials` folder, which is part of `.gitignore`.
