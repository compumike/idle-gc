SHELL=/bin/bash

all: spec

SOURCES=$(shell find src/ -type f -name '*.cr')
SPECS=$(shell find spec/ -type f -name '*.cr')
BENCH_SOURCES=$(shell find bench/ -type f -name '*.cr')

spec: $(SOURCES) $(SPECS)
	crystal spec --verbose

clean:
	rm -f out/idle-gc-bench
	rm -rf ~/.cache/crystal/

spec-repeat: $(SOURCES) $(SPECS)
	runs=10 ; n=1 ; while [[ $$n -le $$runs ]] ; do \
		echo "START RUN $$n of $$runs" ; \
		crystal spec --verbose ; \
		echo "" ; \
		((n = n + 1)) ; \
	done

out/idle-gc-bench: $(SOURCES) $(BENCH_SOURCES)
	mkdir -p out
	crystal build --verbose --stats --progress --threads 8 --release --no-debug -o out/idle-gc-bench bench/idle-gc-bench.cr

bench: out/idle-gc-bench
	bench/run_bench

.PHONY: all spec clean spec-repeat bench
