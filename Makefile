.PHONY: help test ci schematics clean

help:
	@echo "make test        run your testbenches (writes results/local.txt)"
	@echo "make ci          same thing, under the name CI uses (results/ci.txt)"
	@echo "make schematics  synthesize alu/imm/rf/decoder/hart with yosys and"
	@echo "                 render gate-level SVGs with netlistsvg (build/schematics/)"
	@echo "make clean       remove results/ and build/"
	@echo
	@echo "Details:      ./run_test.sh <name> [submission_dir]"
	@echo "Write your own <module>_tb.v for alu, imm, rf, decoder and hart --"
	@echo "see README.md and example/opmux_tb.v from phase 2. There is no"
	@echo "autograder for phase 3; this only runs the testbenches you write."

test:
	@./run_test.sh local

ci:
	@./run_test.sh ci

schematics:
	@./gen_schematics.sh

clean:
	rm -rf results build
