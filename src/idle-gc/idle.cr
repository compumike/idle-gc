class IdleGC
  class Idle
    DEFAULT_IDLE_THRESHOLD = 100.microseconds
    IDLE_DETECTION_REPEAT = 1

    @@idle_threshold : Time::Span = DEFAULT_IDLE_THRESHOLD

    # How long does it take for Fiber.yield to return?
    #
    # This is a measure of whether there are other Fibers waiting to do work.
    def self.fiber_yield_time : Time::Span
      start_time = Time.monotonic
      Fiber.yield
      end_time = Time.monotonic

      end_time - start_time
    end

    # Set the idle threshold for comparing to `IdleGC::Idle.fiber_yield_time`.
    #
    # Experimentally, I found Fiber.yield took about ~5us when idle, and ~500us (or more) when busy, but this will depend on your workload.
    def self.idle_threshold=(v : Time::Span) : Nil
      @@idle_threshold = v
    end

    # Return true if the process is idle, as determined by `#fiber_yield_time` compared to `#idle_threshold=`.
    def self.process_is_idle? : Bool
      # Check multiple times to reduce false positive rate
      IDLE_DETECTION_REPEAT.times.all? { fiber_yield_time < @@idle_threshold }
    end
  end
end
