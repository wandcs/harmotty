@echo off
if "%OHOS_NDK_HOME%"=="" (
  echo OHOS_NDK_HOME is not set 1>&2
  exit /b 1
)
"%OHOS_NDK_HOME%\native\llvm\bin\clang.exe" --target=aarch64-unknown-linux-ohos --sysroot="%OHOS_NDK_HOME%\native\sysroot" -D__MUSL__ -fPIC -fuse-ld=lld -B"%OHOS_NDK_HOME%\native\llvm\bin" %*
