# Run OpsChain — GitHub Action

Run an OpsChain action or workflow from a GitHub Actions job with nothing
but the OpsChain binary: no server, no login. The action installs the
pinned release for the runner's platform, verifies its digest against the
release's `SHA256SUMS.txt`, runs the checked-out repository's action or
workflow on OpsChain's local lane (`--local --approve-all -o json`),
publishes the run document to the job summary and to step outputs,
uploads the run's collected artifacts, and sets the step result from the
run's exit code.

The contract it packages — exit codes, the run document, what a CI run
can and cannot do — is documented in the binary itself:
`opschain docs ci` and the guided lesson `opschain learn 2.8`.

This repository is the whole GitHub packaging: the composite action
above for the **local lane**, and — for pipelines that talk to an
OpsChain **server** — the reusable workflows under
[Server-backed workflows](#server-backed-workflows) with the starter kit
in [`seed/`](seed/README.md).

## Usage

```yaml
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: LimePoint/opschain-action@v1
        id: run
        with:
          version: v5.6.1
          action: deploy
          env: dev
          inputs: |
            release=${{ github.ref_name }}
            dry_run=false
          ref: ${{ github.sha }}
        env:
          OPSCHAIN_MASTER_KEY: ${{ secrets.OPSCHAIN_MASTER_KEY }}
      - run: echo "run ${{ steps.run.outputs.run-id }} finished ${{ steps.run.outputs.status }}"
```

The repository must carry `.opschain/config.yaml` and its action files —
`opschain init` scaffolds them (`opschain docs cli/init`). Running a
workflow instead of an action:

```yaml
      - uses: LimePoint/opschain-action@v1
        with:
          version: v5.6.1
          workflow: nightly
          env: dev
```

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `version` | required | The release to install, e.g. `v5.6.1` (the leading `v` is optional). |
| `action` | — | The action to run. Exactly one of `action` and `workflow`. |
| `workflow` | — | The workflow code (under `.opschain/workflows`) or file to run. |
| `env` | required | The target environment code from `.opschain/config.yaml`. |
| `asset` | — | The target asset code within the environment. |
| `inputs` | — | Typed run inputs, one `key=value` per line; a repeated key builds a list. |
| `ref` | — | A git ref to run a clean snapshot of instead of the working copy. `${{ github.sha }}` pins the job's commit. |
| `approve-all` | `true` | Answer every wait step with its defaults. `false` makes a wait step cancel the run (exit code 3). |
| `artifacts` | `true` | Download the run's artifacts and upload them, with the run document, through `actions/upload-artifact`. |
| `artifact-name` | `opschain-artifacts` | The name of the uploaded bundle. |
| `home` | `${{ runner.temp }}/opschain-home` | The opschain home for the job: the local run history, its keyset and the secret store live here and do not outlive the job. |
| `working-directory` | `.` | The repository directory the run executes in. |
| `timeout` | — | A run timeout such as `30m`. |

## Outputs

| Output | Meaning |
|---|---|
| `run-id` | The run id (`opschain runs show <id> --local`, `opschain logs <id> --local`). |
| `status` | The run's terminal status. |
| `commit` | The revision the run executed: the bare SHA for a clean checkout or a `ref` run; `<sha>+dirty.<digest>` when the job had written into the tree first. |
| `exit-code` | `0` success · `1` failed · `2` usage error · `3` cancelled · `4` timed out. |
| `run-document` | The `-o json` run document on one line (`run`, `steps`, `failed`, `cancelled`, `timed_out`). |
| `artifacts-dir` | Where the artifacts were downloaded, one directory per artifact code. |

The step fails when the exit code is not 0. To read the outputs on a
failed run, set `continue-on-error: true` on the step and check
`exit-code` yourself. On a failing run the step logs are printed in a
collapsed group; they are not part of the run document.

## Secrets

Secret inputs and `secret-vault://` references resolve through the job's
local secret store, encrypted with an age master key. A runner has no OS
keychain (the action always passes `--no-keychain`), so give the job the
key as a masked repository secret exported into the step's environment as
`OPSCHAIN_MASTER_KEY`, and seed the store before the action runs:

```yaml
      - run: printf '%s\n' "$DB_PASSWORD" | opschain secret set db/password --no-keychain
        env:
          OPSCHAIN_HOME: ${{ runner.temp }}/opschain-home
          OPSCHAIN_MASTER_KEY: ${{ secrets.OPSCHAIN_MASTER_KEY }}
          DB_PASSWORD: ${{ secrets.DB_PASSWORD }}
```

(`opschain` is on the PATH after the action's first use in a job; to seed
before the first run, install it with the same version in an earlier step
or run the action once with a trivial action.) `opschain docs cli/secret`
has the key resolution order.

## Images

The local lane never pulls a container image. A step whose `image:` is
not present on the runner fails by name; pull it in a step before the
action, and let the runner's layer cache do the rest.

## Platforms

Linux and macOS runners, `amd64` and `arm64`. Windows runners are refused
with a named error — the local lane's host executor runs on Linux and
macOS today.

## What a CI run cannot do

A CI run is a local run. `change:` steps that spawn a child change on
another node, `content()` / `list()` over the repository, packs declared
with `url:`/`remote:`, workflow retry, and anything that counts as
evidence (who ran it, approvals, audit events) live on a server. To raise
a governed change from a job, use the OpsChain GitHub integration or log
in with an API key minted for the pipeline and create the change on the
server with `--follow` — the exit codes are the same. `opschain docs ci`
lists each pair.

## Server-backed workflows

A pipeline that needs what only a server has — a change anyone can cite
as evidence, approvals, `change:` steps that spawn across nodes, git
sourced packs, the audit trail — raises the run **on the server**
through the OpsChain GitHub integration (`integrations:github`): the job
authenticates itself with its own short-lived GitHub Actions OIDC token,
exchanges it under an administrator-declared trust policy for a
short-lived OpsChain session acting as a service identity, and the
server does the rest. No secret in the repository, no binary on the
runner.

Two reusable workflows package the lane, invoked with `uses:` from a
caller's job:

```yaml
jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
    uses: LimePoint/opschain-action/.github/workflows/opschain-change.yml@v1
    with:
      server-url: https://opschain.example.com
      connection: corp-github
      audience: https://opschain.example.com
      project: payments
      environment: prod
      asset: app
      action: deploy
      ref: ${{ github.sha }}
      inputs: |
        release=${{ github.ref_name }}

  report:
    needs: deploy
    if: always()
    runs-on: ubuntu-latest
    steps:
      - run: echo "change ${{ needs.deploy.outputs.run-id }} finished ${{ needs.deploy.outputs.status }} - ${{ needs.deploy.outputs.url }}"
```

| Workflow | Raises |
|---|---|
| `.github/workflows/opschain-change.yml` | A change: `action` on `/projects/<project>/environments/<environment>[/assets/<asset>]`, pinned to `ref` when given. |
| `.github/workflows/opschain-workflow.yml` | A workflow run: `workflow` (and optionally `version`) of `project`. |

Both exchange the token, create the run, wait for its terminal state
(`timeout-minutes`, polling every `poll-seconds`), write a job summary,
and set the job's result from the run's.

### Inputs

| Input | Default | Meaning |
|---|---|---|
| `server-url` | required | The OpsChain server base URL. |
| `connection` | required | The GitHub connection code to exchange against (`opschain admin github-connections`). |
| `audience` | `opschain` | The OIDC audience to request the Actions token with — must equal the connection's `oidc_audience`. |
| `project` | required | The project code. |
| `environment` | required (change) | The environment code within the project. |
| `asset` | — | The asset code within the environment; empty targets the environment (change only). |
| `action` | required (change) | The OpsChain action to run. |
| `workflow` | required (workflow) | The workflow code to run. |
| `version` | — | The workflow version; the latest published version when empty (workflow only). |
| `inputs` | — | Typed run inputs, one `key=value` per line; a repeated key builds a list. |
| `ref` | — | The git revision to pin the change to; `${{ github.sha }}` pins the job's commit (change only). |
| `git-remote` | — | The project git remote to run from; the project's sole remote when empty (change only). |
| `rationale` | — | Why the run is being raised — shown to approvers as the approval context. |
| `timeout-minutes` | `60` | How long to wait for the terminal state before failing the job. |
| `poll-seconds` | `10` | How often to read the run's state while waiting. |
| `runs-on` | `ubuntu-latest` | The runner label the job runs on. |

### Outputs

| Output | Meaning |
|---|---|
| `run-id` | The change's or workflow run's id. |
| `status` | The terminal status code (`success`, `error`, `failed`, `cancelled`, `aborted`; `timed_out` when the wait expired). |
| `url` | The run's page on the OpsChain server. |

The job fails when the status is not `success`. What the run may do is
the trust policy's service account's own authorisation grants, clamped
to the policy's scope prefix when it carries one (`opschain admin
github-trust-policies create … --scope-prefix /projects/payments`).
Server-side setup, the hand-composed shape with the composite seed
actions (`setup-opschain`, `estate`, `properties`, `secrets`,
`run-action`, `attest`) and the starter callers live in
[`seed/`](seed/README.md); the server's own reference is `opschain docs
integrations-github` and the lesson `opschain learn 13.1`.

### Versioning

`v1` moves with the OpsChain release train: each release re-points the
`v1` tag at the composite action and the workflows that match it, and
cuts a release-pinned tag (`v5.7.0`) beside it. Pin `@v1` to follow the
train, or a release tag to hold still.

## GitHub Enterprise Server

GitHub Actions resolves `uses:` on the instance that runs the workflow,
so an estate on GitHub Enterprise Server mirrors this repository into
the instance and points `uses:` at the mirror:

1. Create the mirror once — an import of
   `https://github.com/LimePoint/opschain-action` into an organisation
   of the instance (for example `tools/opschain-action`), or a bare
   mirror pushed by an administrator (`git clone --mirror` … `git push
   --mirror`).
2. Pin it: callers reference `tools/opschain-action/.github/workflows/opschain-change.yml@v5.7.0`
   (or the mirror's `v1` once it is re-synced) and the composite action
   as `tools/opschain-action@v5.7.0`. GitHub Enterprise Server also
   honours a commit SHA in place of the tag.
3. Re-sync on each OpsChain release: fetch the new tags into the mirror
   and move `v1` with them. Nothing else changes — the workflows reach
   only the OpsChain server the caller names; the GitHub connection on
   that server names the instance host, and its trust policies the
   repositories on it.

The composite action's install step downloads the release from
`LimePoint/opschain-releases` on github.com; an air-gapped instance
pre-stages the release archives on an internal host and points
`scripts/install.sh` at it (or vendors the binary into the runner image)
— the reusable workflows need no download at all.

## Development

`.github/workflows/ci.yml` exercises the action end to end against a
scaffolded repository (`opschain init`) on Linux and macOS runners, and
parses every workflow and composite action in the repository, checking
each embedded shell block with `bash -n`. The reusable workflows run
only against a server with the GitHub integration enabled, so CI
validates their shape, not a live exchange.

## Licence

Apache License 2.0 — see [LICENSE](LICENSE).

## Invitation-only releases

OpsChain releases are gated while the product is invitation-only. LimePoint
issues each invited organisation a GitHub token with read access to the
releases repository. Store it as a repository secret (for example
`OPSCHAIN_RELEASES_TOKEN`) and pass it to the action:

```yaml
- uses: LimePoint/opschain-action@v1
  with:
    version: v5.6.1
    download-token: ${{ secrets.OPSCHAIN_RELEASES_TOKEN }}
    action: hello
    env: dev
```

Without the token the install step fails with a message naming it.
