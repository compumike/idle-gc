require "../spec_helper"

describe IdleGC::Time do
  describe ".monotonic" do
    it "measures elapsed time" do
      before = IdleGC::Time.monotonic
      sleep(5.milliseconds)
      elapsed = IdleGC::Time.monotonic - before
      elapsed.should be >= 5.milliseconds
      elapsed.should be < 1.second
    end

    it "returns a nondecreasing Time::Span" do
      previous = IdleGC::Time.monotonic
      1000.times do
        current = IdleGC::Time.monotonic
        current.should be >= previous
        previous = current
      end
    end
  end
end
