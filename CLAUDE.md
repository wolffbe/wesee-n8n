# wesee-n8n

n8n workflows that read VC deal-flow emails from Outlook, classify them with OpenAI,
extract company properties into a Notion database, and store the pitch deck in OneDrive.

**Setup, the Docker run command, importing, publishing and troubleshooting all live in
[README.md](./README.md).** Read it before changing anything — every flag in the
`docker run` block is load-bearing and documented with the failure it prevents.

## Layout

- `wesee/workflows/*.json` - one file per workflow (main workflow: `wesee.json`;
  the rest are sub-workflows prefixed `wesee - `). These are the source of truth.
- `examples/` - two fictional pitch decks with matching email bodies, one that fits
  the default thesis and one that should be rejected.
- `wesee/credentials/` - exported credentials, gitignored. Never commit it.
- Container `n8n`, volume `n8n_data` (n8n state), port 5678. Host `wesee/` is
  bind-mounted at `/home/node/wesee` in the container.

## Working on this repo

- Host is Windows, Docker Desktop. Run Docker commands from PowerShell; from Git Bash,
  export `MSYS_NO_PATHCONV=1` and `MSYS2_ARG_CONV_EXCL=*` or paths get rewritten.
- **After every `import:workflow`, publish all workflows and restart.** Imports land as
  drafts and sub-workflow calls resolve the published version.
- Debug with `docker exec n8n n8n execute --id <id>` in the foreground. Manual
  executions do not persist node-level run data, so the Executions list will not show
  you where a run actually is.
- n8n expressions are delimited by `{{ }}`. An embedded JSON literal containing `}}`
  closes the expression early and fails at runtime with `invalid syntax`, even though
  the file is valid JSON and the inner JavaScript evaluates fine.
- The config node is deployment-specific. `config.notion.url`, `config.thesis` and
  `config.blacklist.properties.contains` are intentionally blank in git - this is a
  public repository.

## OpenAI

Extraction uses the **Responses API** (`POST /v1/responses`), one call per described
Notion property. The Assistants API was shut down on 2026-08-26; if a node reappears
with `"resource": "assistant"`, it is broken.

Note that a Responses reply always carries a top-level `error` key, `null` on success.
Testing for the key's *presence* marks every successful call as failed - test the value.

Classification still uses the LangChain `lmChatOpenAi` node, which speaks Chat
Completions internally.

## Export after editing in n8n

`make exwf` exports workflows back into `wesee/workflows` (strips pinData, names files
by workflow name). Review the git diff before committing, and check you are not about to
commit a live Notion URL, thesis or blacklist. Never commit decrypted credentials
(`make excrd`).
