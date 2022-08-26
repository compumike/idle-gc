require "../spec_helper"

describe PeriodicGC::Timer do
  it "starts, stops, and frees memory (only_if_idle=false)" do
    PeriodicGC::Timer.stop
    PeriodicGC::Timer.only_if_idle = false
    PeriodicGC::Timer.poll_interval = 1.millisecond
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
    PeriodicGC::Timer.stop
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

    PeriodicGC::Timer.stop
    sleep(10.milliseconds)
  end

  it "starts, stops, and frees memory (only_if_idle=true)" do
    PeriodicGC::Timer.stop
    PeriodicGC.collect
    PeriodicGC::Timer.poll_interval = 1.millisecond
    PeriodicGC::Timer.only_if_idle = true

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
    collection_paused_at = PeriodicGC.last_collected_at.not_nil!
    my_strings << alloc_string(100000)
    GC.stats.bytes_since_gc.should be > 16384

    sleep(15.milliseconds)
    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.last_collected_at.not_nil!.should eq(collection_paused_at)

    # Stop the background worker
    worker_stop_channel.close
    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384
    PeriodicGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    PeriodicGC.last_collected_at.not_nil!.should be > collection_paused_at
    PeriodicGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 25.milliseconds)

    PeriodicGC::Timer.stop
    PeriodicGC.collect
    sleep(10.milliseconds)
  end

  it "PeriodicGC::Timer.force_gc_period= works" do
    PeriodicGC::Timer.stop
    PeriodicGC.collect

    # Start a background worker so we're never idle.
    worker_stop_channel = spawn_background_worker(1.millisecond)

    PeriodicGC::Timer.poll_interval = 1.millisecond
    PeriodicGC::Timer.only_if_idle = true
    PeriodicGC::Timer.force_gc_period = 50.milliseconds
    PeriodicGC.start
    after_start = PeriodicGC.last_collected_at.not_nil!

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)
    my_strings << alloc_string(50000)
    PeriodicGC.last_collected_at.should eq(after_start)
    sleep(5.milliseconds)
    PeriodicGC.last_collected_at.should eq(after_start)

    sleep(50.milliseconds)
    # We can't measure bytes_since_gc since the background worker also thrashes memory.
    # But we can verify a collection has happened.
    after_wait = PeriodicGC.last_collected_at.not_nil!
    after_wait.should be > after_start
    after_wait.should be_close(Time.monotonic, 35.milliseconds)

    # Disable the forced GC period.
    PeriodicGC::Timer.force_gc_period = nil
    sleep(10.milliseconds)
    my_strings << alloc_string(500000)
    sleep(50.milliseconds)
    PeriodicGC.last_collected_at.should eq(after_wait)

    # Cleanup
    worker_stop_channel.close
    PeriodicGC::Timer.stop
    sleep(10.milliseconds)
  end
end
