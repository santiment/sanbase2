# PostgreSQL Setup

## pgvector

You need to install the [pgvector](https://github.com/pgvector/pgvector) extension.

Follow the installation instructions from the pgvector repository. For macOS with Homebrew-installed PostgreSQL:

```bash
git clone --branch v0.8.1 https://github.com/pgvector/pgvector.git
cd pgvector
make
make install
```

> **NOTE:** On macOS, the build may fail with an error like:
>
> ```
> clang: warning: no such sysroot directory: '/Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk'
> fatal error: 'stdio.h' file not found
> ```
>
> This happens because PostgreSQL (installed via Homebrew) was compiled with a hardcoded sysroot
> path (e.g. `MacOSX15.sdk`) that doesn't exist on your system. Setting `SDKROOT` won't help
> because `pg_config` bakes the path directly into the compiler flags.
>
> **Fix:** Create a symlink pointing to your actual SDK:
>
> ```bash
> # Check which SDKs you have
> ls /Library/Developer/CommandLineTools/SDKs/
>
> # Create a symlink for the missing one
> sudo ln -s /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX15.sdk
> ```
>
> Then rebuild:
>
> ```bash
> make clean
> make
> make install
> ```
