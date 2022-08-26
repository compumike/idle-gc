require "../spec_helper"

describe IdleGC::Timer do
  it "starts, stops, and frees memory when idle" do
    IdleGC::Timer.stop
    IdleGC.collect
    IdleGC::Timer.poll_interval = 1.millisecond

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000
    sleep(50.milliseconds)

    IdleGC.start
    sleep(15.milliseconds)

    IdleGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    IdleGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 50.milliseconds)
    IdleGC.last_collected_duration.not_nil!.should be < 10.milliseconds
    GC.stats.bytes_since_gc.should be < 16384

    # Start a background worker.
    worker_stop_channel = spawn_background_worker(1.millisecond)
    sleep(10.milliseconds)
    collection_paused_at = IdleGC.last_collected_at.not_nil!
    my_strings << alloc_string(100000)
    GC.stats.bytes_since_gc.should be > 16384

    sleep(15.milliseconds)
    IdleGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    IdleGC.last_collected_at.not_nil!.should eq(collection_paused_at)

    # Stop the background worker
    worker_stop_channel.close
    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384
    IdleGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    IdleGC.last_collected_at.not_nil!.should be > collection_paused_at
    IdleGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 25.milliseconds)

    IdleGC::Timer.stop
    IdleGC.collect
    sleep(10.milliseconds)
  end

  it "starts, stops, and frees memory regardless of idle (IdleGC::IdleDetection.enabled = false)" do
    IdleGC::Timer.stop
    IdleGC::IdleDetection.enabled = false
    IdleGC::Timer.poll_interval = 1.millisecond

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000

    # Calling start should run a collection synchronously
    IdleGC.start
    IdleGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    IdleGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 50.milliseconds)
    IdleGC.last_collected_duration.not_nil!.should be < 10.milliseconds
    sleep(15.milliseconds)

    IdleGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    IdleGC.last_collected_at.not_nil!.should be_close(Time.monotonic, 50.milliseconds)
    IdleGC.last_collected_duration.not_nil!.should be < 10.milliseconds
    GC.stats.bytes_since_gc.should be < 16384

    my_strings << alloc_string(256000)
    GC.stats.bytes_since_gc.should be > 16384

    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384

    sleep(50.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384

    # Stop IdleGC, and make sure allocations just sit around
    IdleGC.last_checked_at.not_nil!.should be_close(Time.monotonic, 5.milliseconds)
    IdleGC::Timer.stop
    sleep(15.milliseconds)
    (Time.monotonic - IdleGC.last_checked_at.not_nil!).should be < 30.milliseconds
    (Time.monotonic - IdleGC.last_checked_at.not_nil!).should be > 15.milliseconds
    GC.stats.bytes_since_gc.should be < 16384

    my_strings << alloc_string(90000)
    GC.stats.bytes_since_gc.should be > 16384
    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be > 16384

    # Restart it, and make sure they're cleared
    my_strings.clear
    my_strings = nil
    GC.stats.bytes_since_gc.should be > 16384
    IdleGC.start
    sleep(15.milliseconds)
    GC.stats.bytes_since_gc.should be < 16384

    IdleGC::Timer.stop
    IdleGC::IdleDetection.enabled = true
    sleep(10.milliseconds)
  end

  it "IdleGC::Timer.force_gc_period= works" do
    IdleGC::Timer.stop
    IdleGC.collect

    # Start a background worker so we're never idle.
    worker_stop_channel = spawn_background_worker(1.millisecond)

    IdleGC::Timer.poll_interval = 1.millisecond
    IdleGC::Timer.force_gc_period = 50.milliseconds
    IdleGC.start
    after_start = IdleGC.last_collected_at.not_nil!

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)
    my_strings << alloc_string(50000)
    IdleGC.last_collected_at.should eq(after_start)
    sleep(5.milliseconds)
    IdleGC.last_collected_at.should eq(after_start)

    sleep(50.milliseconds)
    # We can't measure bytes_since_gc since the background worker also thrashes memory.
    # But we can verify a collection has happened.
    after_wait = IdleGC.last_collected_at.not_nil!
    after_wait.should be > after_start
    after_wait.should be_close(Time.monotonic, 35.milliseconds)

    # Disable the forced GC period.
    IdleGC::Timer.force_gc_period = nil
    sleep(10.milliseconds)
    my_strings << alloc_string(500000)
    sleep(50.milliseconds)
    IdleGC.last_collected_at.should eq(after_wait)

    # Cleanup
    worker_stop_channel.close
    IdleGC::Timer.stop
    sleep(10.milliseconds)
  end
end
