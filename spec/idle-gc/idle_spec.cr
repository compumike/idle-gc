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
end
