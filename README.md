# Knotical

## Using Docker

1. Install Docker. Follow the instructions on https://docs.docker.com/install/.

1. Build the Knotical image.

    ```
    docker build -t knotical .
    ```

1. Run the Knotical image.

    ```
    docker run -it knotical bash
    ```
    
## Installation on Ubuntu

1. Install Prerequisites

    ```
    apt-get clean
    apt-get update
    apt-get install -qy libppl-dev libmpfr-dev m4 opam subversion
    ```
    
 1. Install OCaml compiler and Dependencies via opam
 
    ```
    opam init
    opam switch 4.06.1
    eval `opam config env`
    opam install oasis ocamlbuild
    opam install apron conf-ppl camllib safa batteries camlp4 core ocamlgraph
    eval `opam config env`
    ```
    
1. Install Fixpoint
  
    ```
    svn checkout https://scm.gforge.inria.fr/anonscm/svn/bjeannet/pkg/fixpoint/
    cd fixpoint/trunk/
    cp Makefile.config.model Makefile.config
    make
    make install
    ```
    
1. Download Interproc and Symkat

    ```
    mkdir deps
    
    svn checkout https://scm.gforge.inria.fr/anonscm/svn/bjeannet/pkg/interproc/ deps/interproc
    
    wget https://perso.ens-lyon.fr/damien.pous/symbolickat/symkat-1.4.tgz --no-check-certificate
    tar -xf symkat-1.4.tgz -C symkat --directory deps/
    ```
    
1. Compile Knotical
   
    ```
    oasis setup
    make
    ```