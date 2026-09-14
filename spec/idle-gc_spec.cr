require "./spec_helper"

class IdleGC
  def self.idle_for_spec(now_ns)
    idle?(now_ns)
  end

  def self.needed_for_spec(bytes : UInt64)
    collection_needed?(bytes)
  end

  def self.activity_count_for_spec
    @@active_count.get
  end

  def self.deadline_for_spec
    @@quiet_until_ns.get
  end
end

describe IdleGC do
  before_each do
    IdleGC.min_bytes_since_gc = IdleGC::DEFAULT_MIN_BYTES_SINCE_GC
    IdleGC.quiet_period = IdleGC::DEFAULT_QUIET_PERIOD
    sleep(15.milliseconds)
  end

  it "becomes idle exactly at the deadline, unless a block is active" do
    IdleGC.busy
    deadline = IdleGC.deadline_for_spec
    IdleGC.idle_for_spec(deadline - 1).should be_false
    IdleGC.idle_for_spec(deadline).should be_true
    IdleGC.busy(0.seconds) do
      IdleGC.idle_for_spec(deadline).should be_false
    end
  end

  it "includes the allocation threshold but always skips zero bytes" do
    threshold = IdleGC::DEFAULT_MIN_BYTES_SINCE_GC
    IdleGC.needed_for_spec(0u64).should be_false
    IdleGC.needed_for_spec(threshold - 1).should be_false
    IdleGC.needed_for_spec(threshold).should be_true
    IdleGC.needed_for_spec(threshold + 1).should be_true
    IdleGC.min_bytes_since_gc = 0
    IdleGC.needed_for_spec(0u64).should be_false
    IdleGC.needed_for_spec(1u64).should be_true
  end

  it "keeps nested blocks busy and returns the block result" do
    IdleGC.busy(0.seconds) do
      IdleGC.activity_count_for_spec.should eq(1)
      IdleGC.busy(0.seconds) { IdleGC.activity_count_for_spec.should eq(2) }
      IdleGC.activity_count_for_spec.should eq(1)
      42
    end.should eq(42)
    IdleGC.activity_count_for_spec.should eq(0)
  end

  it "leaves the quiet period in place when a block raises" do
    expect_raises(Exception, "work failed") do
      IdleGC.busy { raise "work failed" }
    end
    IdleGC.activity_count_for_spec.should eq(0)
    IdleGC.deadline_for_spec.should be > IdleGC::Time.monotonic.total_nanoseconds
  end

  it "does not shorten a heartbeat and does not hold activity" do
    IdleGC.busy(10.milliseconds)
    deadline = IdleGC.deadline_for_spec
    IdleGC.busy(0.seconds)
    IdleGC.busy(0.seconds) { nil }
    IdleGC.deadline_for_spec.should eq(deadline)
    IdleGC.activity_count_for_spec.should eq(0)
  end

  it "uses the period captured at block entry" do
    IdleGC.quiet_period = 10.milliseconds
    IdleGC.busy do
      IdleGC.quiet_period = 0.seconds
      sleep(15.milliseconds)
    end
    IdleGC.deadline_for_spec.should be > IdleGC::Time.monotonic.total_nanoseconds
  end

  it "rejects invalid periods without entering the block" do
    expect_raises(ArgumentError) { IdleGC.busy(-1.nanosecond) }
    expect_raises(ArgumentError) { IdleGC.busy(-1.nanosecond) { fail "entered block" } }
    expect_raises(OverflowError) { IdleGC.busy(Time::Span::MAX) { fail "entered block" } }
    IdleGC.activity_count_for_spec.should eq(0)
  end

  it "tracks overlapping fibers until the last one exits" do
    entered = Channel(Nil).new
    leave = Channel(Nil).new
    done = Channel(Nil).new
    2.times do
      spawn do
        IdleGC.busy(0.seconds) do
          entered.send(nil)
          leave.receive
        end
        done.send(nil)
      end
    end
    2.times { entered.receive }
    IdleGC.activity_count_for_spec.should eq(2)
    leave.send(nil)
    done.receive
    IdleGC.activity_count_for_spec.should eq(1)
    leave.send(nil)
    done.receive
    IdleGC.activity_count_for_spec.should eq(0)
  end

  it "keeps unconditional, allocation-only, and idle collection distinct" do
    IdleGC.min_bytes_since_gc = UInt64::MAX
    IdleGC.busy(0.seconds) do
      IdleGC.collect
      collected = IdleGC.last_collected_at
      IdleGC.collect_if_needed.should be_false
      IdleGC.collect_if_needed_and_idle.should be_false
      IdleGC.last_collected_at.should eq(collected)
      IdleGC.min_bytes_since_gc = 0
      data = alloc_string(100_000)
      IdleGC.collect_if_needed_and_idle.should be_false
      IdleGC.collect_if_needed.should be_true
      data.size.should eq(100_000)
    end
    data = alloc_string(100_000)
    IdleGC.collect_if_needed_and_idle.should be_true
    data.size.should eq(100_000)
  end

  it "coalesces background attempts and respects an extended deadline" do
    IdleGC.min_bytes_since_gc = 0
    IdleGC.collect
    before = IdleGC.last_collected_at
    IdleGC.busy(10.milliseconds)
    IdleGC.background_collect.should be_true
    IdleGC.background_collect.should be_false
    IdleGC.busy(30.milliseconds)
    sleep(15.milliseconds)
    IdleGC.last_collected_at.should eq(before)
    sleep(30.milliseconds)
    IdleGC.last_collected_at.should_not eq(before)
  end

  it "releases the background flag when an attempt finds active work" do
    IdleGC.busy(0.seconds) do
      IdleGC.background_collect.should be_true
      sleep(1.millisecond)
      IdleGC.background_collect.should be_true
      sleep(1.millisecond)
    end
  end
end
