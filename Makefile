# Common to all versions of K
# ===========================

.PHONY: all clean build tangle defn proofs split-tests test deps

all: build split-tests

clean:
	rm -r .build
	find tests/proofs/ -name '*.k' -delete

build: tangle .build/ocaml/ethereum-kompiled/interpreter .build/java/ethereum-kompiled/timestamp

# Tangle from *.md files
# ----------------------

tangle: defn proofs

k_files:=ethereum.k data.k evm.k analysis.k krypto.k verification.k
ocaml_files:=$(patsubst %,.build/ocaml/%,${k_files})
java_files:=$(patsubst %,.build/java/%,${k_files})
defn_files:=${ocaml_files} ${java_files}
defn: $(defn_files)

.build/java/%.k: %.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc --from markdown --to tangle.lua --metadata=code:java $< > $@
.build/ocaml/%.k: %.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc --from markdown --to tangle.lua --metadata=code:ocaml $< > $@

proof_dir=tests/proofs
proof_files=${proof_dir}/sum-to-n-spec.k \
			${proof_dir}/hkg/allowance-spec.k \
			${proof_dir}/hkg/approve-spec.k \
			${proof_dir}/hkg/balanceOf-spec.k \
			${proof_dir}/hkg/transfer-else-spec.k ${proof_dir}/hkg/transfer-then-spec.k \
			${proof_dir}/hkg/transferFrom-else-spec.k ${proof_dir}/hkg/transferFrom-then-spec.k \
			${proof_dir}/bad/hkg-token-buggy-spec.k

proofs: $(proof_files)

tests/proofs/sum-to-n-spec.k: proofs/sum-to-n.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc --from markdown --to tangle.lua --metadata=code:sum-to-n $< > $@

tests/proofs/hkg/%-spec.k: proofs/hkg.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc --from markdown --to tangle.lua --metadata=code:$* $< > $@

tests/proofs/bad/hkg-token-buggy-spec.k: proofs/token-buggy-spec.md
	@echo "==  tangle: $@"
	mkdir -p $(dir $@)
	pandoc --from markdown --to tangle.lua --metadata=code:k $< > $@

# Tests
# -----

split-tests: split-vm-tests split-blockchain-tests

split-vm-tests: \
		  $(patsubst tests/ethereum-tests/%.json,tests/%/make.timestamp, $(wildcard tests/ethereum-tests/VMTests/*/*.json)) \

split-blockchain-tests: \
				  $(patsubst tests/ethereum-tests/%.json,tests/%/make.timestamp, $(wildcard tests/ethereum-tests/BlockchainTests/GeneralStateTests/*/*.json)) \

blockchain_tests=$(wildcard tests/BlockchainTests/*/*/*/*.json)
vm_tests=$(wildcard tests/VMTests/*/*/*.json)
all_tests=${vm_tests} ${blockchain_tests}
skipped_tests=$(wildcard tests/VMTests/vmPerformance/*/*.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/*/*/*_Constantinople.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/stQuadraticComplexityTest/*/*.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/stStaticCall/static_Call50000*/*.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/stStaticCall/static_Return50000*/*.json) \
   $(wildcard tests/BlockchainTests/GeneralStateTests/stStaticCall/static_Call1MB1024Calldepth_d1g0v0/*.json)

passing_tests=$(filter-out ${skipped_tests}, ${all_tests})
passing_vm_tests=$(filter-out ${skipped_tests}, ${vm_tests})
passing_blockchain_tests=$(filter-out ${skipped_tests}, ${blockchain_tests})
passing_targets=${passing_tests:=.test}
passing_vm_targets=${passing_vm_tests:=.test}
passing_blockchain_targets=${passing_blockchain_tests:=.test}

test: $(passing_targets)
vm-test: $(passing_vm_targets)
blockchain-test: $(passing_blockchain_targets)

tests/VMTests/%.test: tests/VMTests/% build
	./vmtest $<
tests/BlockchainTests/%.test: tests/BlockchainTests/% build
	./blockchaintest $<

tests/%/make.timestamp: tests/ethereum-tests/%.json
	@echo "==   split: $@"
	mkdir -p $(dir $@)
	tests/split-test.py $< $(dir $@)
	touch $@

tests/ethereum-tests/%.json:
	@echo "==  git submodule: cloning upstreams test repository"
	git submodule update --init

deps:
	cd tests/ci/rv-k && mvn package
	opam init
	opam repository add k "tests/ci/rv-k/k-distribution/target/release/k/lib/opam" || opam repository set-url k "tests/ci/rv-k/k-distribution/target/release/k/lib/opam"
	opam update
	opam switch 4.03.0+k
	opam install mlgmp zarith uuidm cryptokit secp256k1 bn128


K_BIN=tests/ci/rv-k/k-distribution/target/release/k/bin

# Java Backend Specific
# ---------------------

.build/java/ethereum-kompiled/timestamp: $(java_files)
	@echo "== kompile: $@"
	${K_BIN}/kompile --debug --main-module ETHEREUM-SIMULATION --backend java \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/java

# OCAML Backend Specific
# ----------------------

.build/ocaml/ethereum-kompiled/interpreter: $(ocaml_files) KRYPTO.ml
	@echo "== kompile: $@"
	${K_BIN}/kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/ocaml \
					--hook-namespaces KRYPTO --gen-ml-only -O3 --non-strict
	ocamlfind opt -c .build/ocaml/ethereum-kompiled/constants.ml -package gmp -package zarith
	ocamlfind opt -c -I .build/ocaml/ethereum-kompiled KRYPTO.ml -package cryptokit -package secp256k1 -package bn128
	ocamlfind opt -a -o semantics.cmxa KRYPTO.cmx
	ocamlfind remove ethereum-semantics-plugin
	ocamlfind install ethereum-semantics-plugin META semantics.cmxa semantics.a KRYPTO.cmi KRYPTO.cmx
	${K_BIN}/kompile --debug --main-module ETHEREUM-SIMULATION \
					--syntax-module ETHEREUM-SIMULATION $< --directory .build/ocaml \
					--hook-namespaces KRYPTO --packages ethereum-semantics-plugin -O3 --non-strict
	cd .build/ocaml/ethereum-kompiled && ocamlfind opt -o interpreter constants.cmx prelude.cmx plugin.cmx parser.cmx lexer.cmx run.cmx interpreter.ml -package gmp -package dynlink -package zarith -package str -package uuidm -package unix -package ethereum-semantics-plugin -linkpkg -inline 20 -nodynlink -O3 -linkall
