class IdleGC
  class Request
    DEFAULT_REQUEST_LIMIT = 1u64
    DEFAULT_SYNCHRONOUS = false

    @@request_count : Atomic(UInt64) = Atomic(UInt64).new(0u64)
    @@request_limit : Atomic(UInt64) = Atomic(UInt64).new(DEFAULT_REQUEST_LIMIT)
    @@synchronous : Atomic(UInt8) = Atomic(UInt8).new(DEFAULT_SYNCHRONOUS ? 1u8 : 0u8)

    # Return the current request count.
    def self.request_count : UInt64
      @@request_count.get
    end

    # Return the current request limit.
    def self.request_limit : UInt64
      @@request_limit.get
    end

    # Set the request limit.
    # 
    # (Merely setting the request limit will not cause garbage collection to fire.)
    def self.request_limit=(v : UInt64) : Nil
      @@request_limit.set(v)
    end

    # Returns false (default) if garbage collection happens in the background.
    # Returns true if garbage collection happens synchronously.
    def self.synchronous : Bool
      @@synchronous.get == 1u8
    end

    # Set synchronous=true to force garbage collection to happen synchronously when the request_limit is exceeded.
    #
    # If synchronous=false, a background collection will be scheduled, but will wait until the system is idle.
    #
    # Use synchronous=false for interactive systems, and synchronous=true for non-interactive batch processes.
    def self.synchronous=(v : Bool) : Nil
      @@synchronous.set(v ? 1u8 : 0u8)
    end

    def self.request(incr : UInt64 = 1) : Bool
      lim = @@request_limit.get
      sync = (@@synchronous.get == 1u8)

      old_count = @@request_count.add(incr)

      # See if this addition has tipped the limit
      new_count = old_count + incr
      return false if new_count < lim

      # Do the GC
      if sync
        IdleGC.collect
      else
        IdleGC.background_collect
      end

      # clear the counter
      @@request_count.set(0u64)

      return true
    end
  end
end
