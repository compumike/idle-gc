require "./spec_helper"

describe IdleGC do
  it "IdleGC.collect_if_idle works" do
    IdleGC::Timer.stop
    IdleGC.collect

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    # Idle collection should work
    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000
    IdleGC.collect_if_idle.should be_true
    GC.stats.bytes_since_gc.should be < 16384

    # Start a background worker.
    worker_stop_channel = spawn_background_worker(1.millisecond)
    sleep(10.milliseconds)
    after_worker = IdleGC.last_collected_at.not_nil!

    # Idle collection shouldn't happen
    my_strings << alloc_string(256000)
    GC.stats.bytes_since_gc.should be > 16384
    IdleGC.collect_if_idle.should be_false
    IdleGC.last_collected_at.not_nil!.should eq(after_worker)

    # Stop the background worker
    worker_stop_channel.close
    sleep(15.milliseconds)
    IdleGC.collect_if_idle.should be_true
    IdleGC.last_collected_at.not_nil!.should be > after_worker
    GC.stats.bytes_since_gc.should be < 16384
  end

  it "IdleGC.background_collect works (when idle)" do
    IdleGC::Timer.stop
    IdleGC.collect

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    # Idle collection should work
    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000

    # Request collection
    before_collect = IdleGC.last_collected_at.not_nil!
    IdleGC.background_collect.should be_true
    GC.stats.bytes_since_gc.should be >= 500000

    # Requesting a second collection should do nothing
    IdleGC.background_collect.should be_false

    # Should collect in background
    sleep(25.milliseconds)
    IdleGC.last_collected_at.not_nil!.should be > before_collect
    GC.stats.bytes_since_gc.should be < 16384
  end

  it "IdleGC.background_collect waits (when busy)" do
    IdleGC::Timer.stop
    IdleGC.collect
    IdleGC.background_collect_poll_interval = 1.millisecond

    # Keep pointers around so they aren't freed.
    my_strings = Array(String).new(16)

    # Idle collection should work
    my_strings << alloc_string(500000)
    GC.stats.bytes_since_gc.should be >= 500000

    # Start a background worker.
    worker_stop_channel = spawn_background_worker(1.millisecond)
    sleep(10.milliseconds)

    # Request a collection.
    before_collect = IdleGC.last_collected_at.not_nil!
    IdleGC.background_collect.should be_true

    # Should NOT collect while busy
    sleep(55.milliseconds)
    IdleGC.last_collected_at.not_nil!.should eq(before_collect)

    # Second collection request should have no effect.
    IdleGC.background_collect.should be_false

    # Stop worker. Should collect.
    worker_stop_channel.close
    sleep(5.milliseconds)
    IdleGC.last_collected_at.not_nil!.should be > before_collect

    IdleGC.background_collect_poll_interval = IdleGC::DEFAULT_BACKGROUND_COLLECT_POLL_INTERVAL
  end

  it "IdleGC.background_collect is cancelled by a synchronous IdleGC.collect" do
    IdleGC::Timer.stop
    IdleGC.collect

    # Start a background worker.
    worker_stop_channel = spawn_background_worker(1.millisecond)
    sleep(10.milliseconds)

    # Request background collection
    before_collect = IdleGC.last_collected_at.not_nil!
    IdleGC.background_collect.should be_true

    # Request synchronous collection
    IdleGC.collect
    after_collect = IdleGC.last_collected_at.not_nil!
    after_collect.should be > before_collect

    # Stop worker. Should collect.
    worker_stop_channel.close
    sleep(5.milliseconds)

    # Background collection shouldn't happen
    # Should collect in background
    sleep(25.milliseconds)
    IdleGC.last_collected_at.not_nil!.should eq(after_collect)
  end
end
