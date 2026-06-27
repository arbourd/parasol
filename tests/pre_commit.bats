#!/usr/bin/env bats

setup() {
  HOOK="$PWD/.githooks/pre-commit"
  tmpdir=$(mktemp -d)

  git -C "$tmpdir" init --quiet
  git -C "$tmpdir" config user.email "test@test.com"
  git -C "$tmpdir" config user.name "Test"
  git -C "$tmpdir" commit --allow-empty -m "init" --quiet
}

teardown() {
  rm -rf "$tmpdir"
}

@test 'passes with no staged files' {
  run env GIT_DIR="$tmpdir/.git" GIT_WORK_TREE="$tmpdir" "$HOOK"
  [ "$status" -eq 0 ]
}

@test 'passes with non-secret yaml staged' {
  cat > "$tmpdir/config.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: test
EOF
  git -C "$tmpdir" add config.yaml
  run env GIT_DIR="$tmpdir/.git" GIT_WORK_TREE="$tmpdir" "$HOOK"
  [ "$status" -eq 0 ]
}

@test 'passes with encrypted secret staged' {
  cat > "$tmpdir/mysecret.sops.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test
sops:
  version: 3.0.0
EOF
  git -C "$tmpdir" add mysecret.sops.yaml
  run env GIT_DIR="$tmpdir/.git" GIT_WORK_TREE="$tmpdir" "$HOOK"
  [ "$status" -eq 0 ]
}

@test 'fails when secret is not a sops file' {
  cat > "$tmpdir/secret.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test
stringData:
  key: value
EOF
  git -C "$tmpdir" add secret.yaml
  run env GIT_DIR="$tmpdir/.git" GIT_WORK_TREE="$tmpdir" "$HOOK"
  [ "$status" -eq 1 ]
}

@test 'passes when kind Secret appears nested, not at root' {
  cat > "$tmpdir/config.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: test
data:
  config.yaml: |
    kind: Secret
    name: nested
EOF
  git -C "$tmpdir" add config.yaml
  run env GIT_DIR="$tmpdir/.git" GIT_WORK_TREE="$tmpdir" "$HOOK"
  [ "$status" -eq 0 ]
}

@test 'fails when sops file is missing encryption metadata' {
  cat > "$tmpdir/secret.sops.yaml" <<'EOF'
apiVersion: v1
kind: Secret
metadata:
  name: test
stringData:
  key: plaintext
EOF
  git -C "$tmpdir" add secret.sops.yaml
  run env GIT_DIR="$tmpdir/.git" GIT_WORK_TREE="$tmpdir" "$HOOK"
  [ "$status" -eq 1 ]
}
