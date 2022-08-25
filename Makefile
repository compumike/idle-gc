SHELL=/bin/bash

all: spec

SOURCES=$(shell find src/ -type f -name '*.cr')
SPECS=$(shell find spec/ -type f -name '*.cr')

spec: $(SOURCES) $(SPECS)
	crystal spec --verbose

clean:
	rm -rf ~/.cache/crystal/

spec-repeat: $(SOURCES) $(SPECS)
	runs=10 ; n=1 ; while [[ $$n -le $$runs ]] ; do \
		echo "START RUN $$n of $$runs" ; \
		crystal spec --verbose ; \
		echo "" ; \
		((n = n + 1)) ; \
	done

.PHONY: all spec clean spec-repeat
