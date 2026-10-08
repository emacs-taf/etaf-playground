.DEFAULT_GOAL := check
.NOTPARALLEL:
EMACS ?= emacs
EMACSCLIENT ?= emacsclient
LOAD_PATH = -L . -L lisp -L scripts -L benchmarks -L examples -L ../etaf -L ../etaf-ui -L ../etaf-desktop -L ../ebox -L ../ecss -L ../etaf-db
PYTHON ?= python3
ENTRY_EXAMPLES := $(wildcard examples/*.el)
EXAMPLES := $(ENTRY_EXAMPLES)
EXAMPLE_ELC := $(EXAMPLES:.el=.elc)

.PHONY: all compile examples-read perf-list perf-check gui-doctor gui-research gui-flex gui-grid gui-all gui-desktop \
	check checkdoc load clean

all: check

compile:
	# The Playground is an integration surface.  Compile its dependency graph
	# before compiling the pair; cleaning dependencies without rebuilding them
	# silently forced every Component and Ebox layout through the interpreter.
	$(MAKE) -C ../ecss compile EMACS="$(EMACS)"
	$(MAKE) -C ../ebox compile EMACS="$(EMACS)" ECSS_DIR=../ecss
	$(MAKE) -C ../etaf compile EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-ui compile EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-desktop compile EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-db compile EMACS="$(EMACS)"
	rm -f *.elc scripts/*.elc benchmarks/*.elc tests/*.elc $(EXAMPLE_ELC)
	$(EMACS) -Q --batch $(LOAD_PATH) -L ../etaf/scripts -L ../ebox-playground \
		--eval "(setq load-prefer-newer t byte-compile-error-on-warn t byte-compile-warnings '(not obsolete))" \
		--eval '(load-file "etaf-playground.el")' \
		--eval '(dolist (file (quote ($(foreach file,$(ENTRY_EXAMPLES),"$(file)")))) (load-file file))' \
		--eval '(unless (cl-every (function byte-compile-file) (quote ($(foreach file,$(EXAMPLES),"$(file)") "lisp/etaf-playground-runtime.el" "etaf-playground.el" "scripts/playground-gui-scenarios.el" "scripts/desktop-gui-scenarios.el" "benchmarks/performance-scenarios.el"))) (kill-emacs 1))'

examples-read: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		--eval '(require (quote etaf-playground))' \
		--eval '(dolist (file (quote ($(foreach file,$(ENTRY_EXAMPLES),"$(file)")))) (load (file-name-sans-extension file) nil nil nil))' \
		--eval '(princ "ETAF example modules load OK\\n")'

PERF_TOOL ?= ../scripts/performance.py
perf-list:
	$(PYTHON) "$(PERF_TOOL)" list --root . --scenario-file benchmarks/performance-scenarios.el --scenario 'etaf-playground.*'
perf-check:
	$(PYTHON) "$(PERF_TOOL)" run --root . --scenario-file benchmarks/performance-scenarios.el --mode batch --scenario 'etaf-playground.*' $(PERF_ARGS)

gui-doctor:
	scripts/run-gui-verification.sh doctor

gui-research:
	scripts/run-gui-verification.sh research-shelf

gui-flex:
	scripts/run-gui-verification.sh flex-reference

gui-grid:
	scripts/run-gui-verification.sh grid-reference

gui-all:
	scripts/run-gui-verification.sh all

gui-desktop:
	scripts/run-desktop-gui-verification.sh run


load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(require (quote etaf-playground))' \
		--eval '(princ "etaf-playground load OK\\n")'

checkdoc:
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (append (list "etaf-playground.el" "benchmarks/performance-scenarios.el" "scripts/playground-gui-scenarios.el" "scripts/desktop-gui-scenarios.el") (directory-files-recursively "tests" "\\.el$$") (directory-files-recursively "examples" "\\.el$$"))) (checkdoc-file file)))'

check: structure-check compile acceptance api-check tool-check

clean:
	rm -f *.elc scripts/*.elc benchmarks/*.elc tests/*.elc $(EXAMPLE_ELC)

.PHONY: structure-check setup-hooks
structure-check:
	python3 scripts/check-repository.py
setup-hooks:
	git config --local core.hooksPath .githooks

.PHONY: acceptance
acceptance:
	python3 scripts/run-acceptance.py --emacs "$(EMACS)"

.PHONY: api-check
api-check:
	$(EMACS) -Q --batch -L . $(API_PROVIDER_PATH) --eval '(setq load-prefer-newer t)' -l scripts/check-api.el
API_PROVIDER_PATH = -L ../ecss -L ../ekp -L ../ebox -L ../etaf -L ../etaf-ui -L ../etaf-db -L ../etaf-desktop -L ../ebox-playground

.PHONY: test
test: acceptance

.PHONY: tool-check
tool-check:
	EMACS="$(EMACS)" python3 -m unittest discover -s tests/tools -p 'test_*.py'
