# Compilation Help

## crc32cer: CMake "does not contain a CMakeLists.txt file"

The `crc32cer` NIF depends on Google's `crc32c` library, included as a git submodule under `deps/crc32cer/external/crc32c`. Mix doesn't automatically fetch git submodules when downloading dependencies, so the directory ends up empty.

**Fix:**

```sh
cd deps/crc32cer && git submodule update --init --recursive
cd ../..
mix deps.compile crc32cer --force
```
