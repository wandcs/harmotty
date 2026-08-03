#!/usr/bin/env bash
set -euo pipefail

: "${OHOS_NDK_HOME:?OHOS_NDK_HOME is not set}"

ar="$OHOS_NDK_HOME/native/llvm/bin/llvm-ar.exe"
translated=()
for argument in "$@"; do
  case "$argument" in
    /mnt/*|/home/*|/tmp/*)
      translated+=("$(wslpath -w -- "$argument")")
      ;;
    *)
      translated+=("$argument")
      ;;
  esac
done

exec "$ar" "${translated[@]}"
