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
end
