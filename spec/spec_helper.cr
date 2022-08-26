require "digest/md5"
require "spec"

require "../src/idle-gc"

STDOUT.sync = true

def alloc_string(size : UInt64) : String
  "*" * size
end

def spawn_background_worker(yield_interval : Time::Span = 1.millisecond) : Channel(Nil)
  stop_channel = Channel(Nil).new

  spawn do
    loop do
      break if stop_channel.closed?
      st = Time.monotonic
      s = "Hello, world!"
      loop do
        break if Time.monotonic - st > yield_interval
        s = Digest::MD5.hexdigest(s)
      end
      Fiber.yield
    end
  end

  stop_channel
end
