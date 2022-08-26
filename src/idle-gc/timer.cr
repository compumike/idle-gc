class IdleGC
  class Timer
    DEFAULT_POLL_INTERVAL = 1.second
    DEFAULT_FORCE_GC_PERIOD = 2.minutes
    DEFAULT_BYTES_SINCE_GC_THRESHOLD = 0u64

    @@running : Channel(Nil)? = nil
    @@poll_interval : Time::Span = DEFAULT_POLL_INTERVAL
    @@force_gc_period : Time::Span? = DEFAULT_FORCE_GC_PERIOD
    @@bytes_since_gc_threshold : UInt64 = DEFAULT_BYTES_SINCE_GC_THRESHOLD

    ### PUBLIC METHODS

    # Set the polling interval.
    #
    # Polling more frequently will keep memory usage lower, but will burn more CPU time on garbage collection.
    #
    # The sweet spot is probably seconds to minutes.
    def self.poll_interval=(v : Time::Span) : Nil
      IdleGC.mu.synchronize do
        return if @@poll_interval == v
        @@poll_interval = v

        # Restart if changed while running
        stop_channel = @@running
        if stop_channel
          stop_channel.close
          @@running = spawn_loop
        end
      end
    end

    # Set the force GC period, which forces a GC run when non-idle.
    #
    # Set to nil to disable this behavior.
    #
    # Defaults to 2 minutes.
    def self.force_gc_period=(v : Time::Span?) : Nil
      IdleGC.mu.synchronize do
        @@force_gc_period = v
      end
    end

    # Set to the minimum number of allocated memory bytes required to trigger a collection.
    #
    # Default is 0, meaning that any allocated memory will trigger a collection.
    def self.bytes_since_gc_threshold=(v : UInt64) : Nil
      IdleGC.mu.synchronize do
        @@bytes_since_gc_threshold = v
      end
    end

    # Start a background Fiber that runs garbage collection periodically.
    #
    # (Also runs garbage collection immediately.)
    def self.start : Nil
      IdleGC.mu.synchronize do
        return if @@running

        IdleGC.collect_now!

        @@running = spawn_loop
      end
    end

    # Stop periodic garbage collection. Used for testing.
    #
    # (You don't need to call this. Just let IdleGC die naturally when your program exits.)
    def self.stop : Nil
      IdleGC.mu.synchronize do
        stop_channel = @@running
        if !stop_channel.nil?
          stop_channel.close
          @@running = nil
        end
      end
    end

    ### INTERNAL METHODS

    protected def self.spawn_loop : Channel(Nil)
      stop_channel = Channel(Nil).new

      spawn do
        loop do
          break if stop_channel.closed?

          loop_callback
        end
      end

      stop_channel
    end

    protected def self.should_force_collect? : Bool
      fgp = @@force_gc_period
      return false if fgp.nil?

      lca = IdleGC.last_collected_at
      return true if lca.nil?

      (Time.monotonic - lca) > fgp
    end

    protected def self.loop_callback : Nil
      sleep_period : Time::Span? = nil

      IdleGC.mu.synchronize do
        IdleGC.last_checked_at = Time.monotonic
        sleep_period = @@poll_interval

        if should_force_collect?
          IdleGC.collect_now!
        else
          collect_if_idle_and_needed!
        end
      end

      sleep(sleep_period.not_nil!)
    end

    protected def self.collect_if_idle_and_needed!
      collect_if_needed! if IdleGC::IdleDetection.process_is_idle?
    end

    protected def self.collect_if_needed!
      return if GC.stats.bytes_since_gc <= @@bytes_since_gc_threshold

      IdleGC.collect_now!
    end
  end
end
