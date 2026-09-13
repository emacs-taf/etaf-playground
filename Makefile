.DEFAULT_GOAL := check
.NOTPARALLEL:
EMACS ?= emacs
LOAD_PATH = -L . -L lisp -L scripts -L benchmarks -L ../etaf -L ../etaf-ui -L ../ebox -L ../ecss -L ../tp -L ../etaf-db
EBOX_NATIVE_RELEASE_DIR = $(shell $(EMACS) -Q --batch $(LOAD_PATH) \
	--eval '(setq load-prefer-newer t)' -l ../ebox/ebox.el \
	--eval '(princ (expand-file-name (format "../ebox/native/target/%s/release/" (ebox-native-reflow--rust-target))))')
ENTRY_EXAMPLES := $(wildcard examples/*.el)
EXAMPLES := $(ENTRY_EXAMPLES)
EXAMPLE_ELC := $(EXAMPLES:.el=.elc)
TEST_FILES := $(wildcard tests/*-tests.el)

.PHONY: all compile examples-read test perf perf-prepare perf-evaluator perf-repeatability perf-regressions \
	perf-check gui-doctor gui-research gui-flex gui-grid gui-all \
	check checkdoc load clean

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
	$(MAKE) -C ../etaf-db compile EMACS="$(EMACS)"
	rm -f *.elc scripts/*.elc benchmarks/*.elc tests/*.elc $(EXAMPLE_ELC)
	$(EMACS) -Q --batch $(LOAD_PATH) -L ../etaf/scripts -L ../ebox-playground \
		--eval "(setq load-prefer-newer t byte-compile-error-on-warn t byte-compile-warnings '(not obsolete))" \
		--eval '(load-file "etaf-playground.el")' \
		--eval '(dolist (file (quote ($(foreach file,$(ENTRY_EXAMPLES),"$(file)")))) (load-file file))' \
		--eval '(dolist (file (quote ($(foreach file,$(EXAMPLES),"$(file)")))) (byte-compile-file file))' \
		--eval '(progn (byte-compile-file "lisp/etaf-playground-runtime.el") (byte-compile-file "etaf-playground.el"))' \
		--eval '(byte-compile-file "scripts/playground-gui-scenarios.el")' \
		--eval '(byte-compile-file "scripts/task-workbench-gui-scenarios.el")' \
		--eval '(dolist (file (quote ($(foreach file,$(TEST_FILES),"$(file)")))) (byte-compile-file file))'

examples-read: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		--eval '(require (quote etaf-playground))' \
		--eval '(dolist (file (quote ($(foreach file,$(ENTRY_EXAMPLES),"$(file)")))) (load (file-name-sans-extension file) nil nil nil))' \
		--eval '(princ "ETAF example modules load OK\\n")'

test: examples-read
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		$(foreach test,$(TEST_FILES),-l $(test)) -f ert-run-tests-batch-and-exit

perf:
	$(MAKE) perf-prepare EMACS="$(EMACS)"
	$(MAKE) perf-evaluator EMACS="$(EMACS)"

perf-prepare: compile
	$(MAKE) -C ../ebox native-build EMACS="$(EMACS)" ECSS_DIR=../ecss TP_DIR=../tp

# Run only the already-built product.  This separate target lets an absolute
# max-latency sample start after compilation CPU activity has settled.
perf-evaluator:
	scripts/with-performance-lock.sh env \
	EBOX_NATIVE_REFLOW_MODULE_PATH="$(EBOX_NATIVE_RELEASE_DIR)" \
	"$(EMACS)" -Q --batch $(LOAD_PATH) \
		--eval '(setq load-prefer-newer t native-comp-jit-compilation nil)' \
		--eval '(setq ebox-native-reflow-module-path (getenv "EBOX_NATIVE_REFLOW_MODULE_PATH"))' \
		-l benchmarks/benchmark-research-shelf.el \
		-f etaf-performance-evaluator-batch

# A final hard-max claim must survive three complete independent sample sets.
# The lock above prevents parallel reviewers from benchmarking one another.
perf-repeatability: perf-prepare
	$(MAKE) perf-evaluator EMACS="$(EMACS)"
	$(MAKE) perf-evaluator EMACS="$(EMACS)"
	$(MAKE) perf-evaluator EMACS="$(EMACS)"

# Run package regressions in dependency order.  Keeping them in one recipe
# prevents parallel make from cleaning/recompiling a sibling while another
# package is loading its compiled dependencies.
perf-regressions:
	$(MAKE) -C ../ecss test EMACS="$(EMACS)"
	$(MAKE) -C ../tp test EMACS="$(EMACS)"
	$(MAKE) -C ../ebox test EMACS="$(EMACS)" ECSS_DIR=../ecss TP_DIR=../tp
	$(MAKE) -C ../etaf test EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-ui test EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-db test EMACS="$(EMACS)"
	$(MAKE) test EMACS="$(EMACS)"

# Measure absolute latency before the CPU-heavy regression graph.  Regressions
# still gate the same target, but cannot thermally contaminate product samples.
perf-check:
	$(MAKE) perf-repeatability EMACS="$(EMACS)"
	$(MAKE) perf-regressions EMACS="$(EMACS)"

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

load: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(require (quote etaf-playground))' \
		--eval '(princ "etaf-playground load OK\\n")'

checkdoc:
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (append (list "etaf-playground.el" "benchmarks/benchmark-research-shelf.el" "scripts/playground-gui-scenarios.el" "scripts/task-workbench-gui-scenarios.el") (directory-files-recursively "tests" "\\.el$$") (directory-files-recursively "examples" "\\.el$$"))) (checkdoc-file file)))'

check: structure-check compile acceptance api-check

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
API_PROVIDER_PATH = -L ../ecss -L ../tp -L ../ekp -L ../ebox -L ../etaf -L ../etaf-ui -L ../etaf-db -L ../ebox-playground
