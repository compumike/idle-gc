all: spec

SOURCES=$(shell find src/ -type f -name '*.cr')
SPECS=$(shell find spec/ -type f -name '*.cr')

spec: $(SOURCES) $(SPECS)
	crystal spec --verbose

clean:
	rm -rf ~/.cache/crystal/

.PHONY: all spec clean
