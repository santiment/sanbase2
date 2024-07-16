# Debugging Tips

Sometimes the deployed image crashes without much logs,
especially if something fails during the boot process, when the
supervisor is starting the children.

> You should always catch this on stage! Avoid any difference
> between stage and production. You must always check if stage is
> running good before deploying to production!

A good way to proceed here is to obtain the erl_crash.dump file
from the pod and analyze it.

## Get the erl_crash.dump

To do so, `kubectl edit deployment sanbase-scrapers -n  default` and add the following
command below image:
```yaml
- command:
  - /bin/bash
  - -c
  - sleep 12000
```

This way the mix release is not started and you need to do so manually:
Log into the pod:
```sh
kubectl exec -it <pod name> sh
```
Navigate to the proper dir:
```sh
cd /app/bin
```
Execute the server:
```
./server
```
Wait for the crash, and then copy the dump file to your host.
On your host execute:
```sh
kubectl cp -n default <pod_name>:/app/bin/erl_crash.dump erl_crash.dump
```

## Analyze the dump file

To analyze the dump file, you need to be able to run `:crashdump_viewer.start`
in your iex console. It is possible that this complains that a driver is missing:
```elixir
{:error,
 {{:load_driver, ~c"No driver found"},
  [
    {:wxe_server, :start, 1, [file: ~c"wxe_server.erl", line: 65]},
    {:wx, :new, 1, [file: ~c"wx.erl", line: 115]},
    {:cdv_wx, :init, 1, [file: ~c"cdv_wx.erl", line: 99]},
    {:wx_object, :init_it, 6, [file: ~c"wx_object.erl", line: 416]},
    {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 241]}
  ]}}
```

If this is the case, you need to follow some instructions how to install that.
For example, some instructions how  to install wx widgets can be found on the ASDF page
of Erlang: https://github.com/asdf-vm/asdf-erlang?tab=readme-ov-file#osx

When this is handled, after executing `:crashdump_viewer.start` you will be asked to
locate a dump file.

When the dump file is loaded, the debugging process starts. If the crash happens during boot time,
you will most likely find some useful logs in the `application_controller` process Stack Dump.

For example, this is the message from a pod before terminating:
```
Loading sanbase app...
Starting required dependencies to run the migrations...
Run migrations: UP
{"message":"Migrations already up","timestamp":"2024-07-16T10:26:39.884","level":"info"}
{"message":"    :alarm_handler: {:set, {:system_memory_high_watermark, []}}","timestamp":"2024-07-16T10:26:46.091","level":"notice"}
{"message":"Starting Admin Sanbase.","timestamp":"2024-07-16T10:26:46.201","level":"info"}
{"message":"Running SanbaseWeb.Endpoint with cowboy 2.12.0 at :::4000 (http)","timestamp":"2024-07-16T10:26:46.206","level":"info"}
{"message":"Access SanbaseWeb.Endpoint at http://localhost:4000","timestamp":"2024-07-16T10:26:46.207","level":"info"}
Runtime terminating during boot (terminating)

Crash dump is being written to: erl_crash.dump...done
[os_mon] cpu supervisor port (cpu_sup): Erlang has closed
[os_mon] memory supervisor port (memsup): Erlang has closed
```

There is no indication what is wrong.

But the Stack Dump of the `application_controller` process has the following:
```erlang
{application_start_failure,sanbase,{{shutdown,{failed_to_start_child,'Elixir.Sanbase.ClickhouseRepo.ReadOnly',{shutdown,{failed_to_start_child,'Elixir.DBConnection.ConnectionPool',{{badmatch,{error,{#{message => <<\"pool size must be greater or equal to 1, got 0\">>,'__struct__' => 'Elixir.ArgumentError','__exception__' => true},[{'Elixir.DBConnection.ConnectionPool.Pool',init,1,[{file,\"lib/db_connection/connection_pool/pool.ex\"},{line,20}]},{supervisor,init,1,[{file,\"supervisor.erl\"},{line,330}]},{gen_server,init_it,2,[{file,\"gen_server.erl\"},{line,980}]},{gen_server,init_it,6,[{file,\"gen_server.erl\"},{line,935}]},{proc_lib,init_p_do_apply,3,[{file,\"proc_lib.erl\"},{line,241}]}]}}},[{'Elixir.DBConnection.ConnectionPool',init,1,[{file,\"lib/db_connection/connection_pool.ex\"},{line,57}]},{gen_server,init_it,2,[{file,\"gen_server.erl\"},{line,980}]},{gen_server,init_it,6,[{file,\"gen_server.erl\"},{line,935}]},{proc_lib,init_p_do_apply,3,[{file,\"proc_lib.erl\"},{line,241}]}]}}}}},{'Elixir.Sanbase.Application',start,[normal,[]]}}}
```

From this we now have a clear idea what might be wrong: `pool size must be greater or equal to 1, got 0`
