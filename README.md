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

## Development

`.github/workflows/ci.yml` exercises the action end to end against a
scaffolded repository (`opschain init` on a checkout of
`LimePoint/opschain-getting-started`) on Linux and macOS runners.

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
