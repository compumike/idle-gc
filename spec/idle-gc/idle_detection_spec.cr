require "../spec_helper"

describe IdleGC::IdleDetection do
  it "#process_is_idle? is accurate" do
    100.times do
      IdleGC::IdleDetection.process_is_idle?.should be_true
      sleep(100.microseconds)
    end

    # Start a worker
    worker_stop_channel = spawn_background_worker(1.millisecond)
    100.times do
      IdleGC::IdleDetection.process_is_idle?.should be_false
      sleep(100.microseconds)
    end

    # Stop the worker
    worker_stop_channel.close
    sleep(10.milliseconds)
    100.times do
      IdleGC::IdleDetection.process_is_idle?.should be_true
      sleep(100.microseconds)
    end
  end

  it "#enabled= works" do
    # Should be enabled by default
    IdleGC::IdleDetection.enabled.should be_true
    IdleGC::IdleDetection.process_is_idle?.should be_true

    # Start a worker
    worker_stop_channel = spawn_background_worker(1.millisecond)
    Fiber.yield
    IdleGC::IdleDetection.process_is_idle?.should be_false

    # Disable idle detection
    IdleGC::IdleDetection.enabled = false
    IdleGC::IdleDetection.enabled.should be_false
    IdleGC::IdleDetection.process_is_idle?.should be_true
    IdleGC::IdleDetection.enabled = true
    IdleGC::IdleDetection.enabled.should be_true
    IdleGC::IdleDetection.process_is_idle?.should be_false
    IdleGC::IdleDetection.enabled = false
    IdleGC::IdleDetection.process_is_idle?.should be_true
    IdleGC::IdleDetection.enabled = true
    IdleGC::IdleDetection.process_is_idle?.should be_false

    # Stop the worker
    worker_stop_channel.close
    sleep(5.milliseconds)
    IdleGC::IdleDetection.enabled.should be_true
    IdleGC::IdleDetection.process_is_idle?.should be_true
  end
end
