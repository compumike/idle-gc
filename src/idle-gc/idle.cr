class IdleGC
  class Idle
    DEFAULT_IDLE_THRESHOLD = 100.microseconds
    DEFAULT_IDLE_DETECTION_REPEAT = 1u8

    @@enabled : Atomic(UInt8) = Atomic(UInt8).new(1u8)
    @@idle_detection_repeat : Atomic(UInt8) = Atomic(UInt8).new(DEFAULT_IDLE_DETECTION_REPEAT)
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
      IdleGC.mu.synchronize do
        @@idle_threshold = v
      end
    end

    # Idle detection is enabled by default, but it is based on a heuristic which may be inaccurate, so you may wish to disable it by calling `IdleGC::Idle.enabled = false`.
    #
    # If disabled, then `#process_is_idle?` will always return true.
    #
    # If your workload is not latency-sensitive, then running GC periodicially regardless of whether the system is idle may be optimal.
    def self.enabled=(v : Bool) : Nil
      @@enabled.set(v ? 1u8 : 0u8)
    end

    def self.enabled : Bool
      @@enabled.get == 1u8
    end

    # To reduce idle false-positives, we can check multiple times in succession. Default is 1.
    def self.idle_detection_repeat=(v : UInt8) : Nil
      raise ArgumentError.new("Must be at least 1") if v == 0
    end

    # Return true if the process is idle, as determined by `#fiber_yield_time` compared to `#idle_threshold=`.
    def self.process_is_idle? : Bool
      return true unless enabled

      # Check multiple times to reduce false positive rate
      idle_detection_repeat = @@idle_detection_repeat.get
      idle_detection_repeat.times.all? { fiber_yield_time < @@idle_threshold }
    end
  end
end
