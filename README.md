# idle-gc

**IdleGC** makes it easy to automatically run garbage collection when your [Crystal](https://crystal-lang.org/) process is otherwise idle. Idle-time garbage collection is beneficial because:

1. It reduces the memory size of the program, reducing operating costs, and
2. It may prevent the garbage collector from running during a latency-sensitive period.

**IdleGC** is easy-to-use. Simply call `IdleGC.start` and a new background Fiber will continuously poll for idle periods, garbage collecting as needed.

If you have request-oriented processing, such as in a web server, you may additionally call `IdleGC.background_collect` near the end of your request cycle. This won't block your response from completing, but will only collect after the system is idle. It's perfectly safe to call `IdleGC.background_collect` multiple times, and it will only schedule a single collection if it hasn't had a chance to run yet.

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
