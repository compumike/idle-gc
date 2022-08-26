require "../spec_helper"

describe IdleGC::Idle do
  it "#process_is_idle? is accurate" do
    100.times do
      IdleGC::Idle.process_is_idle?.should be_true
      sleep(100.microseconds)
    end

    # Start a worker
    worker_stop_channel = spawn_background_worker(1.millisecond)
    100.times do
      IdleGC::Idle.process_is_idle?.should be_false
      sleep(100.microseconds)
    end

    # Stop the worker
    worker_stop_channel.close
    sleep(10.milliseconds)
    100.times do
      IdleGC::Idle.process_is_idle?.should be_true
      sleep(100.microseconds)
    end
  end

  it "#enabled= works" do
    # Should be enabled by default
    IdleGC::Idle.enabled.should be_true
    IdleGC::Idle.process_is_idle?.should be_true

    # Start a worker
    worker_stop_channel = spawn_background_worker(1.millisecond)
    Fiber.yield
    IdleGC::Idle.process_is_idle?.should be_false

    # Disable idle detection
    IdleGC::Idle.enabled = false
    IdleGC::Idle.enabled.should be_false
    IdleGC::Idle.process_is_idle?.should be_true
    IdleGC::Idle.enabled = true
    IdleGC::Idle.enabled.should be_true
    IdleGC::Idle.process_is_idle?.should be_false
    IdleGC::Idle.enabled = false
    IdleGC::Idle.process_is_idle?.should be_true
    IdleGC::Idle.enabled = true
    IdleGC::Idle.process_is_idle?.should be_false

    # Stop the worker
    worker_stop_channel.close
    sleep(5.milliseconds)
    IdleGC::Idle.enabled.should be_true
    IdleGC::Idle.process_is_idle?.should be_true
  end
end
