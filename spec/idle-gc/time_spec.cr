require "../spec_helper"

describe IdleGC::Time do
  describe ".monotonic" do
    it "is very close to ::Time.monotonic" do
      idlegc_monotonic = IdleGC::Time.monotonic
      crystal_monotonic = ::Time.monotonic
      difference = crystal_monotonic - idlegc_monotonic

      difference.should be >= 0.0.seconds
      difference.should be < 1.0e-3.seconds
    end

    it "returns a nondecreasing Time::Span" do
      samples : Array(Time::Span) = 1000.times.map { |i|
        Fiber.yield if (i % 3 == 0)
        IdleGC::Time.monotonic
      }.to_a

      samples.each_index do |i|
        next if i == 0

        difference = samples[i] - samples[i - 1]
        difference.should be >= 0.0.seconds
        difference.should be < 1.0e-3.seconds
      end
    end
  end
end
