Installing KEVM
===============

In a nutshell, to install KEVM on an Ubuntu 16.04 machine, run:

```

sudo apt-get update
sudo apt-get install make gcc maven openjdk-8-jdk flex opam pkg-config libmpfr-dev autoconf libtool pandoc zlib1g-dev
git submodule update --init # Initialize submodules
cd .build/secp256k1 && ./autogen.sh && ./configure --enable-module-recovery && make && sudo make install # install secp256k1 from bitcoin-core
cd ../..
make deps # Build dependencies not installed by package manager
eval `opam config env` # add OCAML installation to path
make # Build Project

```

To run the Ethereum VMTests and GeneralStateTests, run `make test`

To run one of the proofs, run `./Build prove $specfile`
