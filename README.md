# idle-gc

**IdleGC v2** runs garbage collection during quiet periods between application requests or jobs. Call `IdleGC.start`, then wrap work in `IdleGC.busy { ... }`. When the last block finishes, a background fiber waits for the quiet period before attempting collection. A polled `force_gc_period` (default 2 minutes, matching the Golang runtime) runs regardless of busy/idle status.

Only work inside `IdleGC.busy { ... }` is tracked as busy (not-idle). New work can arrive just after a check. GC still pauses the whole process.

**IdleGC** is currently used in production on:

-  [HeyOnCall](https://heyoncall.com/) - [website monitoring](https://heyoncall.com/website-monitoring) and on-call alerting
-  [Total Real Returns](https://totalrealreturns.com/) - inflation and dividend-adjusted stock charts

## CRYSTAL_LOAD_DEBUG_INFO=0

You may want to set the environment variable `CRYSTAL_LOAD_DEBUG_INFO=0` before running your Crystal-compiled binary. This prevents the Crystal runtime from loading debugging info when an Exception occurs and the runtime attempts to print a backtrace. The loading of debug info causes a one-time massive spike in memory usuage, which is not freed by garbage collection. The attemtped loading of debug info, and the memory spike, happens even when the binary was compiled with `crystal build --no-debug`, which strips out debug info.

For web servers built using [kemal](https://github.com/kemalcr/kemal) or similar, note that Exceptions happen even if the client simply disconnects before a response is sent. This does not indicate an issue with your server software, but will still cause a massive memory spike unless you have `CRYSTAL_LOAD_DEBUG_INFO=0` set.

Of course, if you do set `CRYSTAL_LOAD_DEBUG_INFO=0`, you will not see method names in your backtrace.

This `CRYSTAL_LOAD_DEBUG_INFO=0` setting is currently undocumented. You can find it in the Crystal code here: https://github.com/crystal-lang/crystal/blob/1.5.0/src/exception/call_stack/stackwalk.cr#L11

(This is only related to **IdleGC** because if you're reading this README, you likely want to avoid large sudden spikes in memory usage.)

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     idle-gc:
       github: compumike/idle-gc
   ```

2. Run `shards install`

## Usage

Configure defaults before starting:

```crystal
require "idle-gc"

IdleGC.quiet_period = 10.milliseconds
IdleGC.min_bytes_since_gc = 1_048_576u64 # 1 MiB
IdleGC.start

IdleGC.busy do
  # Handle one request or job here.
end
```

An `IdleGC.busy { ... }` block marks the process as being non-idle until the block finishes.

Without a block, `IdleGC.busy` is a heartbeat that postpones collection for the specified period. Shorter heartbeats never shorten an existing quiet period deadline.

`IdleGC.collect` always collects synchronously. `IdleGC.collect_if_needed` checks allocations versus `min_bytes_since_gc`. `IdleGC.collect_if_needed_and_idle` also checks activity. Both conditional methods return whether they collected.

By default, the timer attempts collection even while busy after two minutes (matching the Golang runtime), but still checks `min_bytes_since_gc`. Set `IdleGC::Timer.force_gc_period = nil` before starting to disable this forced periodic GC.

(IdleGC v1 was very different, based on automatic idle detection which no longer applies in newer versions of Crystal.)

## Development

Run `./d_dev` to bring up a docker container for development, where you can easily run:

```shell
make spec     # to run unit tests
make bench    # to run benchmarks
```

## Author

- [compumike](https://github.com/compumike) - creator and maintainer
