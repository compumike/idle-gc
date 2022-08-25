require "digest/md5"

require "./spec_helper"

describe PeriodicGC do
  it "starts, stops, and frees memory" do
    PeriodicGC.poll_interval = 1.millisecond
    PeriodicGC.last_checked_at.should be_nil
    PeriodicGC.last_collected_at.should be_nil
    PeriodicGC.last_collected_duration.should be_nil

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000

    PeriodicGC.start
    PeriodicGC.last_checked_at.should be_nil
    PeriodicGC.last_collected_at.should be_nil
    PeriodicGC.last_collected_duration.should be_nil
    sleep(15.milliseconds)

    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 50.milliseconds)
    PeriodicGC.last_collected_duration.not_nil!.should be < 10.milliseconds
    GC.stats.bytes_since_gc.should be < 16384

    my_strings << alloc_string(256000)
    GC.stats.bytes_since_gc.should be > 16384

    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384

    sleep(50.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384

    # Stop PeriodicGC, and make sure allocations just sit around
    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.stop
    sleep(15.milliseconds)
    (Time.monotonic - PeriodicGC.last_checked_at.not_nil!).should be < 30.milliseconds
    (Time.monotonic - PeriodicGC.last_checked_at.not_nil!).should be > 15.milliseconds
    GC.stats.bytes_since_gc.should be < 16384

    my_strings << alloc_string(90000)
    GC.stats.bytes_since_gc.should be > 16384
    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be > 16384

    # Restart it, and make sure they're cleared
    my_strings.clear
    my_strings = nil
    GC.stats.bytes_since_gc.should be > 16384
    PeriodicGC.start
    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384
    PeriodicGC.stop
  end

  it "#process_is_idle? is accurate" do

    PeriodicGC.process_is_idle?.should be_true

    # Start a worker
    stop_channel = Channel(Nil).new
    spawn do
      loop do
        break if stop_channel.closed?
        st = Time.monotonic
        s = "Hello, world!"
        loop do
          break if Time.monotonic - st > 1.millisecond
          s = Digest::MD5.hexdigest(s)
        end
        Fiber.yield
      end
    end
    PeriodicGC.process_is_idle?.should be_false

    # Stop the worker
    stop_channel.close
    sleep(10.milliseconds)
    PeriodicGC.process_is_idle?.should be_true
  end
end
