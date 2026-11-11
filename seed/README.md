# Seed kit — the server-backed lane

Starter material for pipelines that talk to an OpsChain **server**
(`integrations:github`): a workflow authenticates itself with its own
short-lived GitHub Actions OIDC token, exchanges it under an
administrator-declared trust policy for a short-lived OpsChain session
acting as a service identity, and raises changes, reads the estate,
properties and secrets at run time — the repository holds no OpsChain
configuration and no standing credential.

Server-side setup (an OpsChain administrator, once):

```
opschain admin github-connections create corp-github \
  --app-id <app id> --oidc-audience <your server URL> \
  --private-key-file <the App's .pem>
opschain admin service-accounts create gha-payments
opschain admin github-trust-policies create payments-main \
  --connection corp-github --repository 'my-org/payments' \
  --ref 'refs/heads/main' --service-account gha-payments \
  --scope-prefix /projects/payments
```

## `workflows/` — starter callers of the reusable workflows

- `server-change.yml` — on push to `main`, raise a change on the server
  through `LimePoint/opschain-action/.github/workflows/opschain-change.yml@v1`
  and end the job with the change's result.
- `server-workflow.yml` — nightly (and by hand), start a run of a
  project workflow through `opschain-workflow.yml@v1`.
- `composed-fan-out.yml` — the hand-composed shape: one job queries the
  estate, the next fans out across the assets that exist right now, each
  leg pulling its own resolved properties and masked secrets through the
  composite actions below, and attests the outcome back.

Copy a caller into `.github/workflows/` of the repository the trust
policy covers, set the server URL, connection, audience and target, and
push. The caller's job needs `permissions: id-token: write` and nothing
else: no secret, no binary.

## `actions/` — the composite seed actions

Vendor these into `.github/actions/` of your repository (or your
organisation's actions repository) and adjust the `uses:` paths in
`composed-fan-out.yml`:

- `setup-opschain/` — requests the run's OIDC token, exchanges it, masks
  the minted session token and exports `OPSCHAIN_SERVER_URL` /
  `OPSCHAIN_TOKEN` to the job environment.
- `estate/` — authorisation-scoped estate lookup under a node path,
  emitted as JSON and as a ready-made `strategy.matrix` output.
- `properties/` — pulls a node's properties document as JSON.
- `secrets/` — resolves `secret-vault://` references against a node and
  delivers them as masked environment variables.
- `run-action/` — invokes an OpsChain action against a node and awaits
  its conclusion (what the reusable `opschain-change.yml` packages).
- `attest/` — reports this workflow's outcome back against an OpsChain
  change, so GitHub-initiated work lands in the audit trail like native
  runs.

What the exchanged session may read and do is the trust policy's
service account's own authorisation grants, clamped to the policy's
scope prefix when it carries one — scope both to exactly what the
pipeline needs. The full story on the server: `opschain docs
integrations-github` and `opschain learn 13.1`.
