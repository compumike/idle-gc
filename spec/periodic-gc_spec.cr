require "./spec_helper"

# Start a background worker.

describe PeriodicGC do
  it "starts, stops, and frees memory (only_if_idle=false)" do
    PeriodicGC.stop
    PeriodicGC.only_if_idle = false
    PeriodicGC.poll_interval = 1.millisecond
    PeriodicGC.last_checked_at.should be_nil
    PeriodicGC.last_collected_at.should be_nil
    PeriodicGC.last_collected_duration.should be_nil

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000

    # Calling start should run a collection synchronously
    PeriodicGC.start
    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 50.milliseconds)
    PeriodicGC.last_collected_duration.not_nil!.should be < 10.milliseconds
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
    sleep(10.milliseconds)
  end

  it "#process_is_idle? is accurate" do
    10.times do
      PeriodicGC.process_is_idle?.should be_true
      sleep(100.microseconds)
    end

    # Start a worker
    worker_stop_channel = spawn_background_worker(1.millisecond)
    10.times do
      PeriodicGC.process_is_idle?.should be_false
      sleep(100.microseconds)
    end

    # Stop the worker
    worker_stop_channel.close
    sleep(10.milliseconds)
    10.times do
      PeriodicGC.process_is_idle?.should be_true
      sleep(100.microseconds)
    end
  end

  it "starts, stops, and frees memory (only_if_idle=true)" do
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

    PeriodicGC.stop
    sleep(10.milliseconds)
  end

  it "#collect_if_idle works" do
    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)


    # Idle collection should work
    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000
    PeriodicGC.collect_if_idle.should be_true
    GC.stats.bytes_since_gc.should be < 16384

    # Start a background worker.
    worker_stop_channel = spawn_background_worker(1.millisecond)
    sleep(10.milliseconds)

    # Idle collection shouldn't happen
    my_strings << alloc_string(256000)
    GC.stats.bytes_since_gc.should be > 16384
    PeriodicGC.collect_if_idle.should be_false
    GC.stats.bytes_since_gc.should be > 16384

    # Stop the background worker
    worker_stop_channel.close
    sleep(15.milliseconds)
    PeriodicGC.collect_if_idle.should be_true
    GC.stats.bytes_since_gc.should be < 16384
  end

  it "#force_gc_period= works" do
    # Start a background worker so we're never idle.
    worker_stop_channel = spawn_background_worker(1.millisecond)

    PeriodicGC.stop
    PeriodicGC.poll_interval = 1.millisecond
    PeriodicGC.only_if_idle = true
    PeriodicGC.force_gc_period = 20.milliseconds
    PeriodicGC.start

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000

    sleep(5.milliseconds)
    GC.stats.bytes_since_gc.should be >= 500000

    sleep(25.milliseconds)
    # We can't measure bytes_since_gc since the background worker also thrashes memory.
    # But we can verify a collection has happened.
    lca = PeriodicGC.last_collected_at.not_nil!
    lca.should be_close(Time.monotonic, 35.milliseconds)

    # Disable the forced GC period.
    PeriodicGC.force_gc_period = nil
    sleep(10.milliseconds)
    my_strings << alloc_string(500000)
    sleep(30.milliseconds)
    PeriodicGC.last_collected_at.should eq(lca)

    # Cleanup
    worker_stop_channel.close
    PeriodicGC.stop
    sleep(10.milliseconds)
  end
end
