#!/usr/bin/env bash
set -euo pipefail

: "${OHOS_NDK_HOME:?OHOS_NDK_HOME is not set}"

clang="$OHOS_NDK_HOME/native/llvm/bin/clang.exe"
sysroot="$(wslpath -w -- "$OHOS_NDK_HOME/native/sysroot")"
llvm_bin="$(wslpath -w -- "$OHOS_NDK_HOME/native/llvm/bin")"
translated=()

to_windows_path() {
  wslpath -w -- "$1"
}

for argument in "$@"; do
  case "$argument" in
    /mnt/*|/home/*|/tmp/*)
      translated+=("$(to_windows_path "$argument")")
      ;;
    @/mnt/*|@/home/*|@/tmp/*)
      translated+=("@$(to_windows_path "${argument:1}")")
      ;;
    -I/mnt/*|-I/home/*|-I/tmp/*|-L/mnt/*|-L/home/*|-L/tmp/*|-B/mnt/*|-B/home/*|-B/tmp/*)
      translated+=("${argument:0:2}$(to_windows_path "${argument:2}")")
      ;;
    -Wl,--version-script=/mnt/*|-Wl,--version-script=/home/*|-Wl,--version-script=/tmp/*)
      translated+=("-Wl,--version-script=$(to_windows_path "${argument#*=}")")
      ;;
    *)
      translated+=("$argument")
      ;;
  esac
done

exec "$clang" --target=aarch64-unknown-linux-ohos --sysroot="$sysroot" \
  -D__MUSL__ -fPIC -fuse-ld=lld -B"$llvm_bin" "${translated[@]}"
