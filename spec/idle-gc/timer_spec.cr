require "../spec_helper"

# Each program gets its own process-lifetime timer.
def timer_program(code : String)
  source = "require \"./src/idle-gc\"\n" + code
  output = IO::Memory.new
  status = Process.run("crystal", ["eval", source], output: output, error: output, chdir: File.expand_path("../..", __DIR__))
  status.success?.should be_true, output.to_s
end

describe IdleGC::Timer do
  it "starts once and collects after the last block without waiting for a poll" do
    timer_program <<-'CODE'
      IdleGC::Timer.poll_interval = 10.seconds
      IdleGC::Timer.force_gc_period = nil
      IdleGC.min_bytes_since_gc = 0
      IdleGC.start
      IdleGC.start
      raise "collected at startup" if IdleGC.last_collected_at
      IdleGC.busy(20.milliseconds) { "*" * 100_000 }
      raise "collected on exit" if IdleGC.last_collected_at
      sleep(5.milliseconds)
      raise "collected before deadline" if IdleGC.last_collected_at
      sleep(50.milliseconds)
      raise "missed deadline collection" unless IdleGC.last_collected_at
    CODE
  end

  it "forces only when due and enough bytes have been allocated" do
    timer_program <<-'CODE'
      IdleGC::Timer.poll_interval = 5.milliseconds
      IdleGC::Timer.force_gc_period = 30.milliseconds
      IdleGC.min_bytes_since_gc = UInt64::MAX
      IdleGC.start
      IdleGC.busy do
        IdleGC.min_bytes_since_gc = 0
        data = "*" * 100_000
        sleep(10.milliseconds)
        raise "forced too early" if IdleGC.last_collected_at
        IdleGC.min_bytes_since_gc = UInt64::MAX
        sleep(60.milliseconds)
        raise "ignored allocation gate" if IdleGC.last_collected_at
        IdleGC.min_bytes_since_gc = 0
        data = "*" * 100_000
        sleep(20.milliseconds)
        raise "did not force while busy" unless IdleGC.last_collected_at
        raise "lost data" unless data.size == 100_000
      end
    CODE
  end

  it "polls without activity and honors disabled forcing" do
    timer_program <<-'CODE'
      IdleGC::Timer.poll_interval = 5.milliseconds
      IdleGC::Timer.force_gc_period = nil
      IdleGC.min_bytes_since_gc = 0
      IdleGC.start
      IdleGC.busy do
        sleep(30.milliseconds)
        raise "collected while busy" if IdleGC.last_collected_at
      end
      sleep(40.milliseconds)
      raise "never collected" unless IdleGC.last_collected_at
      before = IdleGC.last_collected_at
      data = "*" * 100_000
      sleep(20.milliseconds)
      raise "poll missed allocation" if before == IdleGC.last_collected_at
      raise "lost data" unless data.size == 100_000
    CODE
  end
end
