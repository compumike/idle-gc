require "./spec_helper"

# Start a background worker.

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
    worker_stop_channel = spawn_background_worker(1.millisecond)
    PeriodicGC.process_is_idle?.should be_false

    # Stop the worker
    worker_stop_channel.close
    sleep(10.milliseconds)
    PeriodicGC.process_is_idle?.should be_true
  end

  it "works with only_is_idle=true" do
    PeriodicGC.stop
    PeriodicGC.poll_interval = 1.millisecond
    PeriodicGC.only_if_idle = true

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000
    sleep(50.milliseconds)

    PeriodicGC.start
    sleep(15.milliseconds)

    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 50.milliseconds)
    PeriodicGC.last_collected_duration.not_nil!.should be < 10.milliseconds
    GC.stats.bytes_since_gc.should be < 16384

    # Start a background worker.
    worker_stop_channel = spawn_background_worker(1.millisecond)
    sleep(10.milliseconds)
    collection_paused_at = PeriodicGC.last_collected_at
    my_strings << alloc_string(256000)
    GC.stats.bytes_since_gc.should be > 16384

    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be > 16384
    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.last_collected_at.not_nil!.should eq(collection_paused_at)

    # Stop the background worker
    worker_stop_channel.close
    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384
    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 25.milliseconds)
  end
end
