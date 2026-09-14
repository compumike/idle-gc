require "../spec_helper"

describe IdleGC::Request do
  before_each do
    IdleGC.min_bytes_since_gc = 0
    IdleGC.collect
    sleep(15.milliseconds)
  end

  after_each do
    IdleGC.min_bytes_since_gc = IdleGC::DEFAULT_MIN_BYTES_SINCE_GC
  end
  it "does synchronous collects" do
    IdleGC::Request.request_count.should eq(0)
    IdleGC::Request.request_limit = 1
    IdleGC::Request.request_limit.should eq(1)
    IdleGC::Request.synchronous = true

    data = alloc_string(100_000)
    before_request = IdleGC.last_collected_at.not_nil!
    IdleGC::Request.request.should be_true
    after_request = IdleGC.last_collected_at.not_nil!
    after_request.should be > before_request

    data.size.should eq(100_000)
    IdleGC::Request.request_count.should eq(0)
    IdleGC::Request.synchronous = false
  end

  it "does background collects" do
    IdleGC::Request.request_count.should eq(0)
    IdleGC::Request.request_limit = 1
    IdleGC::Request.request_limit.should eq(1)

    data = alloc_string(100_000)
    before_request = IdleGC.last_collected_at.not_nil!
    IdleGC::Request.request.should be_true
    after_request = IdleGC.last_collected_at.not_nil!
    after_request.should eq(before_request)

    sleep(10.milliseconds)
    after_sleep = IdleGC.last_collected_at.not_nil!
    after_sleep.should be > before_request

    IdleGC::Request.request_count.should eq(0)
  end

  it "does synchronous collects with higher limit" do
    IdleGC::Request.request_count.should eq(0)
    IdleGC::Request.request_limit = 10
    IdleGC::Request.request_limit.should eq(10)
    IdleGC::Request.synchronous = true

    # Request 5
    IdleGC::Request.request(5).should be_false
    # Request 3
    IdleGC::Request.request(3).should be_false
    # Request 1
    IdleGC::Request.request.should be_false

    # Triggering request
    data = alloc_string(100_000)
    before_request = IdleGC.last_collected_at.not_nil!
    IdleGC::Request.request.should be_true
    after_request = IdleGC.last_collected_at.not_nil!
    after_request.should be > before_request

    IdleGC::Request.request_count.should eq(0)
    IdleGC::Request.request_limit = 1
    IdleGC::Request.request_limit.should eq(1)
    IdleGC::Request.synchronous = false
  end

  it "does background collects with higher limit" do
    IdleGC::Request.request_count.should eq(0)
    IdleGC::Request.request_limit = 10
    IdleGC::Request.request_limit.should eq(10)

    # Request 5
    IdleGC::Request.request(5).should be_false
    # Request 3
    IdleGC::Request.request(3).should be_false
    # Request 1
    IdleGC::Request.request.should be_false

    # Triggering request
    data = alloc_string(100_000)
    before_request = IdleGC.last_collected_at.not_nil!
    IdleGC::Request.request.should be_true
    after_request = IdleGC.last_collected_at.not_nil!
    after_request.should eq(before_request)

    sleep(10.milliseconds)
    after_sleep = IdleGC.last_collected_at.not_nil!
    after_sleep.should be > before_request

    IdleGC::Request.request_count.should eq(0)
    IdleGC::Request.request_limit = 1
    IdleGC::Request.request_limit.should eq(1)
  end
end
