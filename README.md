# idle-gc

**IdleGC** makes it easy to automatically run garbage collection when your [Crystal](https://crystal-lang.org/) process is otherwise idle. Idle-time garbage collection is beneficial because:

1. It reduces the memory size of the program, reducing operating costs, and
2. It may prevent the garbage collector from running during a latency-sensitive period.

**IdleGC** is easy-to-use. Simply call `IdleGC.start` and a new background Fiber will continuously poll for idle periods, garbage collecting as needed.

If you have request-oriented processing, such as in a web server, you may additionally call `IdleGC.background_collect` near the end of your request cycle. This won't block your response from completing, but will only collect after the system is idle. It's perfectly safe to call `IdleGC.background_collect` multiple times, and it will only schedule a single collection if it hasn't had a chance to run yet.

**IdleGC** is currently used in production on [Total Real Returns](https://totalrealreturns.com/).

## Benchmarks

It's hard to get reliable memory usage benchmarks. Test it in your own application.

| Configuration | Heap Size (MiB) | Runtime (s) | Max Latency (ms) | Memory Savings (%) | Recommended? |
| --- | --- | --- | --- | --- | --- |
| (off) | 588.79 | 9.90 | 153 | (baseline) | _ |
| Timer | 532.82 | 9.90 | 154 | -9.5% | _ |
| Synchronous | 369.60 | 9.90 | 151 | -37.2% | _ |
| Background | 369.80 | 9.90 | 151 | -37.2% | _ |
| Timer + Synchronous | 362.15 | 9.90 | 151 | -38.5% | _ |
| Timer + Background | 361.73 | 9.90 | 151 | -38.6% | **RECOMMENDED** |
| Timer + request_limit=2 | 579.28 | 9.90 | 167 | -1.6% | _ |

(Timer means a periodic idle GC. Synchronous means a blocking `IdleGC.collect` call within the request processing. Background means calling `IdleGC.background_collect` within the request processing. Benchmarks are run via `make bench` within `d_dev`. Results shown are best-of-5.)

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

Timer-based polling:

```crystal
require "idle-gc"

IdleGC.start
```

Background collection after a request:
```crystal
def your_request_handler(context : HTTP::Server::Context)
   ... your code here...

   IdleGC.background_collect
end
```

## Development

Run `./d_dev` to bring up a docker container for development, where you can easily run:

```shell
make spec     # to run unit tests
make bench    # to run benchmarks
```

## Author

- [compumike](https://github.com/compumike) - creator and maintainer
