class IdleGC
  class Timer
    DEFAULT_POLL_INTERVAL   = 10.seconds
    DEFAULT_FORCE_GC_PERIOD = 2.minutes

    @@running = Atomic(Bool).new(false)
    @@poll_interval : ::Time::Span = DEFAULT_POLL_INTERVAL
    @@force_gc_period : ::Time::Span? = DEFAULT_FORCE_GC_PERIOD

    # Set the polling interval before starting. Defaults to 10 seconds.
    def self.poll_interval=(v : ::Time::Span) : Nil
      raise ArgumentError.new("poll_interval must be positive") if v <= ::Time::Span.zero
      IdleGC.mu.synchronize do
        raise "Configure the timer before starting it" if running?
        @@poll_interval = v
      end
    end

    # Force an allocation-gated collection even when busy. Defaults to 2 minutes.
    # Set to nil before starting to disable forced collections.
    def self.force_gc_period=(v : ::Time::Span?) : Nil
      raise ArgumentError.new("force_gc_period must be positive") if v && v <= ::Time::Span.zero
      IdleGC.mu.synchronize do
        raise "Configure the timer before starting it" if running?
        @@force_gc_period = v
      end
    end

    def self.running? : Bool
      @@running.get
    end

    # Start one periodic polling fiber for the lifetime of the process.
    def self.start : Nil
      IdleGC.mu.synchronize do
        return if running?
        started_at = IdleGC::Time.monotonic
        spawn do
          loop do
            sleep(@@poll_interval)
            IdleGC.mu.synchronize do
              force_period = @@force_gc_period
              last_collection = IdleGC.last_collected_at || started_at
              if force_period && IdleGC::Time.monotonic - last_collection >= force_period
                # Force a collection even while busy.
                IdleGC.collect_if_needed
              else
                # Collect only if idle.
                IdleGC.collect_if_needed_and_idle
              end
            end
          end
        end
        @@running.set(true)
      end
    end
  end
end
