.DEFAULT_GOAL := check
.NOTPARALLEL:
EMACS ?= emacs
LOAD_PATH = -L . -L lisp -L scripts -L benchmarks -L examples -L ../etaf -L ../etaf-ui -L ../etaf-desktop -L ../ebox -L ../ecss -L ../etaf-db
EBOX_NATIVE_RELEASE_DIR = $(shell $(EMACS) -Q --batch $(LOAD_PATH) \
	--eval '(setq load-prefer-newer t)' -l ../ebox/ebox.el \
	--eval '(princ (expand-file-name (format "../ebox/native/target/%s/release/" (ebox-native-reflow--rust-target))))')
ENTRY_EXAMPLES := $(wildcard examples/*.el)
EXAMPLES := $(ENTRY_EXAMPLES)
EXAMPLE_ELC := $(EXAMPLES:.el=.elc)
TEST_FILES := $(wildcard tests/*-tests.el)

.PHONY: all compile examples-read perf perf-prepare perf-evaluator perf-repeatability perf-regressions \
	perf-check gui-doctor gui-research gui-flex gui-grid gui-all \
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
		--eval '(unless (cl-every (function byte-compile-file) (quote ($(foreach file,$(EXAMPLES),"$(file)") "lisp/etaf-playground-runtime.el" "etaf-playground.el" "scripts/playground-gui-scenarios.el" "scripts/task-workbench-gui-scenarios.el" "benchmarks/benchmark-task-workbench.el" "benchmarks/profile-task-workbench.el" $(foreach file,$(TEST_FILES),"$(file)")))) (kill-emacs 1))'

examples-read: compile
	$(EMACS) -Q --batch $(LOAD_PATH) --eval '(setq load-prefer-newer t)' \
		--eval '(require (quote etaf-playground))' \
		--eval '(dolist (file (quote ($(foreach file,$(ENTRY_EXAMPLES),"$(file)")))) (load (file-name-sans-extension file) nil nil nil))' \
		--eval '(princ "ETAF example modules load OK\\n")'

perf:
	$(MAKE) perf-prepare EMACS="$(EMACS)"
	$(MAKE) perf-evaluator EMACS="$(EMACS)"

perf-prepare: compile
	$(MAKE) -C ../ebox native-build EMACS="$(EMACS)" ECSS_DIR=../ecss

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
	$(MAKE) -C ../ecss  EMACS="$(EMACS)"
	$(MAKE) -C ../ebox  EMACS="$(EMACS)" ECSS_DIR=../ecss
	$(MAKE) -C ../etaf  EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-ui  EMACS="$(EMACS)"
	$(MAKE) -C ../etaf-db  EMACS="$(EMACS)"
	$(MAKE)  EMACS="$(EMACS)"

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
	$(EMACS) -Q --batch --eval '(progn (require (quote checkdoc)) (dolist (file (append (list "etaf-playground.el" "benchmarks/benchmark-research-shelf.el" "benchmarks/benchmark-task-workbench.el" "scripts/playground-gui-scenarios.el" "scripts/task-workbench-gui-scenarios.el") (directory-files-recursively "tests" "\\.el$$") (directory-files-recursively "examples" "\\.el$$"))) (checkdoc-file file)))'

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

.PHONY: perf-workbench
perf-workbench:
	@wb_log=$$(mktemp "$${TMPDIR:-/tmp}/etaf-workbench.XXXXXX"); \
	wb_status=0; \
	scripts/with-performance-lock.sh "$(EMACS)" -Q --batch $(LOAD_PATH) \
		--eval '(setq load-prefer-newer t native-comp-jit-compilation nil)' \
		-l benchmarks/benchmark-task-workbench.el \
		-f etaf-workbench-benchmark-batch 2>"$$wb_log" || wb_status=$$?; \
	printf 'log=%s\n' "$$wb_log"; \
	exit $$wb_status

.PHONY: tool-check
tool-check:
	EMACS="$(EMACS)" python3 -m unittest discover -s tests/tools -p 'test_*.py'

.PHONY: profile-workbench
profile-workbench:
	@wb_log=$$(mktemp "$${TMPDIR:-/tmp}/etaf-workbench-profile.XXXXXX"); \
	wb_status=0; \
	ETAF_WORKBENCH_PROFILE_SCENARIO="$(or $(SCENARIO),row-toggle)" \
	scripts/with-performance-lock.sh "$(EMACS)" -Q --batch $(LOAD_PATH) \
		--eval '(setq load-prefer-newer t native-comp-jit-compilation nil)' \
		-l benchmarks/profile-task-workbench.el \
		-f etaf-workbench-profile-batch 2>"$$wb_log" || wb_status=$$?; \
	printf 'log=%s\n' "$$wb_log"; \
	exit $$wb_status
