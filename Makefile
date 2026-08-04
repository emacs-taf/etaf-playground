EMACS ?= emacs
LOAD_PATH = -L . -L ../etaf -L ../etaf-ui -L ../emacs-box

.PHONY: all compile test check checkdoc load clean

all: check

compile:
	rm -f *.elc tests/*.elc
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		--eval '(load-file "etaf-playground.el")' \
		--eval '(byte-compile-file "etaf-playground.el")'

test: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		-l tests/etaf-playground-tests.el -f ert-run-tests-batch-and-exit

load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(require (quote etaf-playground))' \
		--eval '(princ "etaf-playground load OK\n")'

checkdoc:
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (directory-files "." t)) (when (string-suffix-p ".el" file) (checkdoc-file file))))'

check: checkdoc compile test

clean:
	rm -f *.elc tests/*.elc
