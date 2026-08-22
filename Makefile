EMACS ?= emacs
LOAD_PATH = -L . -L ../etaf -L ../etaf-ui -L ../ebox -L ../ecss -L ../tp -L ../etaf-sqlite
EXAMPLE_EL := examples/research-shelf.el

.PHONY: all compile examples-read test perf check checkdoc load clean

all: check

compile:
	# The Playground is an integration surface.  Compile its dependency graph
	# before compiling the pair; cleaning dependencies without rebuilding them
	# silently forced every Component and Ebox layout through the interpreter.
	$(MAKE) -C ../ecss compile EMACS="$(EMACS)"
	$(MAKE) -C ../tp compile EMACS="$(EMACS)"
	$(MAKE) -C ../ebox compile EMACS="$(EMACS)" ECSS_DIR=../ecss TP_DIR=../tp
	$(MAKE) -C ../etaf compile EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-ui compile EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-sqlite compile EMACS="$(EMACS)"
	rm -f *.elc tests/*.elc examples/*.elc
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		--eval '(load-file "etaf-playground.el")' \
		--eval '(dolist (file (quote ($(foreach file,$(EXAMPLE_EL),"$(file)")))) (byte-compile-file file))' \
		--eval '(byte-compile-file "etaf-playground-catalog.el")' \
		--eval '(byte-compile-file "etaf-playground.el")' \
		--eval '(byte-compile-file "tests/etaf-playground-tests.el")'

examples-read: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		--eval '(require (quote etaf-playground))' \
		--eval '(load-file "examples/research-shelf.el")' \
		--eval '(let ((database (make-temp-file "etaf-playground-read-" nil ".sqlite")) (buffer " *etaf-playground-read*")) (unwind-protect (let ((etaf-research-shelf-database-file database)) (etaf-playground-mount-example buffer "research-shelf")) (etaf-playground-close buffer) (when (file-exists-p database) (delete-file database))))' \
		--eval '(princ "ETAF example modules load OK\\n")'

test: examples-read
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		-l tests/etaf-playground-tests.el -f ert-run-tests-batch-and-exit

perf: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		-l scripts/benchmark-research-shelf.el

load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(require (quote etaf-playground))' \
		--eval '(princ "etaf-playground load OK\\n")'

checkdoc:
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (list "etaf-playground.el" "etaf-playground-catalog.el" "tests/etaf-playground-tests.el" "examples/research-shelf.el" "scripts/benchmark-research-shelf.el")) (checkdoc-file file)))'

check: checkdoc test

clean:
	rm -f *.elc tests/*.elc examples/*.elc
