#!/usr/bin/env bash

if [ -z "$EMACS" ] ; then
    EMACS="emacs"
fi

for n in *-tests.el; do
    $EMACS -batch -l tests.el -l "$n" -f ert-run-tests-batch-and-exit
done;