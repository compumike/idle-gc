require "./spec_helper"

describe PeriodicGC do
  it "PeriodicGC.collect_if_idle works" do
    PeriodicGC::Timer.stop
    PeriodicGC.collect

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
    after_worker = PeriodicGC.last_collected_at.not_nil!

    # Idle collection shouldn't happen
    my_strings << alloc_string(256000)
    GC.stats.bytes_since_gc.should be > 16384
    PeriodicGC.collect_if_idle.should be_false
    PeriodicGC.last_collected_at.not_nil!.should eq(after_worker)

    # Stop the background worker
    worker_stop_channel.close
    sleep(15.milliseconds)
    PeriodicGC.collect_if_idle.should be_true
    PeriodicGC.last_collected_at.not_nil!.should be > after_worker
    GC.stats.bytes_since_gc.should be < 16384
  end
end
