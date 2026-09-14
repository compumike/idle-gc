require "./idle-gc/request"
require "./idle-gc/time"
require "./idle-gc/timer"

# IdleGC runs garbage collection during quiet periods between application work.
# Call IdleGC.start, then wrap requests or jobs in IdleGC.busy { ... }.
#
# IdleGC.collect always collects. IdleGC.collect_if_needed checks allocations,
# and IdleGC.collect_if_needed_and_idle also checks for activity.
# Use IdleGC.background_collect to request a background attempt.
class IdleGC
  VERSION = "2.0.0"

  DEFAULT_QUIET_PERIOD       = 10.milliseconds
  DEFAULT_MIN_BYTES_SINCE_GC = 1_048_576u64

  @@mu = Mutex.new(Mutex::Protection::Reentrant)
  @@last_checked_at : ::Time::Span? = nil
  @@last_collected_at : ::Time::Span? = nil
  @@last_collected_duration : ::Time::Span? = nil
  @@background_collect_running = Atomic(Bool).new(false)
  @@active_count = Atomic(Int64).new(0)
  @@quiet_until_ns = Atomic(Int64).new(0)
  @@quiet_period_ns = Atomic(Int64).new(DEFAULT_QUIET_PERIOD.total_nanoseconds.to_i64)
  @@min_bytes_since_gc = Atomic(UInt64).new(DEFAULT_MIN_BYTES_SINCE_GC)

  ##########
  # START:

  # Start periodic collection. Calling start again does nothing.
  def self.start : Nil
    Timer.start
  end

  ##########
  # CONFIGURATION:

  # How long should we wait after work finishes? Defaults to 10 milliseconds.
  def self.quiet_period : ::Time::Span
    @@quiet_period_ns.get.nanoseconds
  end

  def self.quiet_period=(v : ::Time::Span) : Nil
    @@quiet_period_ns.set(quiet_period_ns_from_now(v))
  end

  # Minimum allocations for conditional collection. Defaults to 1 MiB.
  # Setting this to zero still requires at least one allocated byte.
  def self.min_bytes_since_gc : UInt64
    @@min_bytes_since_gc.get
  end

  def self.min_bytes_since_gc=(v : UInt64) : Nil
    @@min_bytes_since_gc.set(v)
  end

  ##########
  # BUSY (NOT-IDLE) TRACKING:

  # Mark activity without a block. Call again if the work outlasts the period.
  def self.busy(quiet_period : ::Time::Span = self.quiet_period) : Nil
    extend_quiet_until(quiet_period_ns_from_now(quiet_period))

    # Schedule a background collection if there are no block-tracked work running.
    background_collect if Timer.running? && @@active_count.get == 0
  end

  # Postpone idle collection until the block and its quiet period finish.
  # This is the recommended interface for wrapping application work.
  def self.busy(quiet_period : ::Time::Span = self.quiet_period, &)
    period_ns = quiet_period_ns_from_now(quiet_period)

    # Increment the active / busy count.
    @@active_count.add(1)

    begin
      extend_quiet_until(period_ns)

      # Run the block.
      yield
    ensure
      begin
        # Publish the deadline before another fiber can see the count reach zero.
        extend_quiet_until(period_ns)
      ensure
        remaining = @@active_count.sub(1) - 1

        # Just to be safe, make sure active_count never goes negative.
        if remaining < 0
          @@active_count.compare_and_set(remaining, 0)
        end
      end

      # If finishing this block means the process is now idle, schedule a background collection.
      background_collect if remaining == 0 && Timer.running?
    end
  end

  ##########
  # METADATA:

  # Relative to IdleGC::Time.monotonic, when did IdleGC last check whether or not to run garbage collect?
  #
  # Returns nil if we've never checked.
  def self.last_checked_at : ::Time::Span?
    mu.synchronize do
      return @@last_checked_at
    end
  end

  # Relative to IdleGC::Time.monotonic, when did IdleGC last initiate GC.collect?
  #
  # Returns nil if we've never collected.
  def self.last_collected_at : ::Time::Span?
    mu.synchronize do
      return @@last_collected_at
    end
  end

  # How long did GC.collect take to run?
  #
  # Returns nil if we've never collected.
  def self.last_collected_duration : ::Time::Span?
    mu.synchronize do
      return @@last_collected_duration
    end
  end

  ##########
  # GARBAGE COLLECTION:

  # Explicitly force collection now.
  def self.collect : Nil
    mu.synchronize do
      start_time = IdleGC::Time.monotonic
      GC.collect
      end_time = IdleGC::Time.monotonic

      @@last_checked_at = start_time
      @@last_collected_at = start_time
      @@last_collected_duration = end_time - start_time
    end
  end

  # Collect if enough memory has been allocated, even if we're busy.
  def self.collect_if_needed : Bool
    mu.synchronize do
      @@last_checked_at = IdleGC::Time.monotonic
      return false unless collection_needed?
      collect
      true
    end
  end

  # Collect if enough memory has been allocated and no tracked work is busy.
  def self.collect_if_needed_and_idle : Bool
    mu.synchronize do
      @@last_checked_at = IdleGC::Time.monotonic
      return false unless collection_needed?
      return false unless idle?
      collect
      true
    end
  end

  ##########
  # BACKGROUND COLLECTION FIBER:

  # Calling background_collect requests one background attempt by spinning up a new fiber.
  # Returns false if one is already pending.
  # A request near the end of an attempt may be missed; the periodic poll retries.
  def self.background_collect : Bool
    # Atomic flag ensures at most one of these background collection fibers runs at a time.
    return false if @@background_collect_running.swap(true)

    begin
      spawn do
        begin
          loop do
            # If active_count>0, there's no need for us to wait.
            # (The block will spawn a new background_collect fiber when it finishes and active_count drops to zero.)
            break unless @@active_count.get == 0

            remaining = @@quiet_until_ns.get - IdleGC::Time.monotonic.total_nanoseconds
            if remaining > 0
              # Sleep for a bit longer than the remaining quiet period, to avoid spinning too fast.
              sleep((remaining + 1000).nanoseconds)
            else
              collect_if_needed_and_idle
              break
            end
          end
        ensure
          @@background_collect_running.set(false)
        end
      end
    rescue ex
      @@background_collect_running.set(false)
      raise ex
    end
    true
  end

  ##########
  # INTERNAL METHODS:

  protected def self.mu : Mutex
    @@mu
  end

  private def self.idle?(now_ns = IdleGC::Time.monotonic.total_nanoseconds) : Bool
    @@active_count.get == 0 && now_ns >= @@quiet_until_ns.get
  end

  private def self.collection_needed?(bytes = GC.stats.bytes_since_gc) : Bool
    bytes > 0 && bytes >= min_bytes_since_gc
  end

  private def self.quiet_period_ns_from_now(period : ::Time::Span) : Int64
    raise ArgumentError.new("quiet_period must be nonnegative") if period < ::Time::Span.zero
    ns = period.total_nanoseconds.to_i64
    # Check the deadline too, before entering a busy block.
    (IdleGC::Time.monotonic.total_nanoseconds + ns).to_i64
    ns
  end

  private def self.extend_quiet_until(period_ns : Int64) : Nil
    deadline = (IdleGC::Time.monotonic.total_nanoseconds + period_ns).to_i64
    previous = @@quiet_until_ns.get
    while previous < deadline
      # A shorter heartbeat must not overwrite a longer quiet period.
      # Looped atomic update, which terminates if (1) we successfully set the new quiet_until_ns deadline, or (2) the quiet_until_ns deadline is already longer.
      previous, changed = @@quiet_until_ns.compare_and_set(previous, deadline)
      break if changed
    end
  end
end
