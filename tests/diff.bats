#!/usr/bin/env bats

setup() {
  SCRIPT="$PWD/diff.sh"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures"
  tmpdir=$(mktemp -d)

  # Fake helm returns known Kubernetes YAML based on --version argument,
  # allowing functional tests to run without network access or a real chart registry.
  mkdir -p "$tmpdir/bin"
  cat > "$tmpdir/bin/helm" <<'HELM'
#!/bin/bash
case "$1" in
  repo|pull) exit 0 ;;
  template)
    prev=""
    for arg in "$@"; do
      if [[ "$prev" == "--version" ]]; then
        version="$arg"
        break
      fi
      prev="$arg"
    done
    case "$version" in
      1.0.0)
        cat <<'YAML'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-chart
  labels:
    helm.sh/chart: test-chart-1.0.0
    app.kubernetes.io/version: "1.0.0"
spec:
  replicas: 1
YAML
        ;;
      2.0.0)
        cat <<'YAML'
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-chart
  labels:
    helm.sh/chart: test-chart-2.0.0
    app.kubernetes.io/version: "2.0.0"
spec:
  replicas: 2
YAML
        ;;
    esac
    ;;
esac
HELM
  chmod +x "$tmpdir/bin/helm"

  cat > "$tmpdir/configmap.yaml" <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: test
data:
  key: value
EOF
}

teardown() {
  rm -rf "$tmpdir"
}

# Argument validation

@test 'shows help with --help flag' {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test 'exits 1 when --source-file is missing' {
  run bash "$SCRIPT" --target-file "$FIXTURES/target.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 1 ]
}

@test 'exits 1 when --source-file is not a HelmRelease' {
  run bash "$SCRIPT" --source-file "$tmpdir/configmap.yaml" --target-file "$FIXTURES/target.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 1 ]
}

@test 'exits 1 when --target-file is missing' {
  run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 1 ]
}

@test 'exits 1 when --target-file is not a HelmRelease' {
  run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --target-file "$tmpdir/configmap.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 1 ]
}

@test 'exits 1 when --helmrepositories-path is missing' {
  run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --target-file "$FIXTURES/target.yaml"
  [ "$status" -eq 1 ]
}

# Functional tests

@test 'output includes the path to the target file' {
  PATH="$tmpdir/bin:$PATH" run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --target-file "$FIXTURES/target.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 0 ]
  [[ "$output" == *"fixtures/target.yaml"* ]]
}

@test 'output shows version change between source and target' {
  PATH="$tmpdir/bin:$PATH" run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --target-file "$FIXTURES/target.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0.0"* ]]
  [[ "$output" == *"2.0.0"* ]]
}

@test 'output contains a diff block when resources differ' {
  PATH="$tmpdir/bin:$PATH" run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --target-file "$FIXTURES/target.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 0 ]
  [[ "$output" == *'```diff'* ]]
}

@test 'output shows no changes when resources are identical' {
  PATH="$tmpdir/bin:$PATH" run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --target-file "$FIXTURES/same-target.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml'
  [ "$status" -eq 0 ]
  [[ "$output" == *"No changes"* ]]
}

@test 'remove-common-labels strips helm version labels from diff' {
  PATH="$tmpdir/bin:$PATH" run bash "$SCRIPT" --source-file "$FIXTURES/source.yaml" --target-file "$FIXTURES/target.yaml" --helmrepositories-path './tests/fixtures/helmrepositories/*.yaml' --remove-common-labels
  [ "$status" -eq 0 ]
  [[ "$output" != *"helm.sh/chart"* ]]
}
