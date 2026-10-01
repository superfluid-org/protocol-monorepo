#
# Configurations
#
CABAL ?= cabal
DEV_TARGETS ?= test
TEST_SHOW_DETAILS_MODE ?= direct # alternatively: always | failure | never
TEST_PROP_NUM_RUNS ?= 1000
TEST_BUILDDIR ?= dist-test
TEST_COVERAGE_BUILDDIR ?= dist-coverage
DOCS_BUILDDIR ?= dist-docs
WASM_BUILDDIR ?= dist-wasm

CABAL_TEST     = $(CABAL) --builddir=$(TEST_BUILDDIR)
CABAL_COVERAGE = $(CABAL) --builddir=$(TEST_COVERAGE_BUILDDIR)
CABAL_DOCS     = $(CABAL) --builddir=$(DOCS_BUILDDIR)
CABAL_WASM     = $(CABAL) --builddir=$(WASM_BUILDDIR)

TEST_OPTIONS = \
	-O0 \
	--test-show-details=$(TEST_SHOW_DETAILS_MODE) \
	--test-options="--maximum-generated-tests=$(TEST_PROP_NUM_RUNS)"

default: build

.PHONY: check

#
# Build
#
build:
	$(CABAL) v2-build all

build-test:
	$(CABAL_TEST) v2-build all

build-wasm:
	$(CABAL_WASM) v2-build -v --with-compiler wasm32-wasi-ghc --with-hc-pkg wasm32-wasi-ghc-pkg semantic-money
	wasm32-wasi-ghc \
		-odir $(PWD)/$(WASM_BUILDDIR)/wasm -hidir $(PWD)/$(WASM_BUILDDIR)/wasm -stubdir $(PWD)/$(WASM_BUILDDIR)/wasm \
		-o $(PWD)/$(WASM_BUILDDIR)/semantic-money.wasm -no-hs-main \
		-optl-mexec-model=reactor -optl-Wl,--export=hs_init,--export=uu_flow2 \
		-ipkgs/semantic-money/src \
		-package-db ~/.cabal/store/ghc-$$(wasm32-wasi-ghc --numeric-version)/package.db \
		-package data-default \
		pkgs/semantic-money/wasm/Exports.hs

clean:
	rm -rf $(DOCS_BUILDDIR)
	rm -rf $(TEST_BUILDDIR)
	rm -rf $(TEST_COVERAGE_BUILDDIR)
	rm -rf dist-*

.PHONY: default build* clean

#
# Testing
#
test:
	$(CABAL_TEST) v2-test all --enable-tests \
		$(TEST_OPTIONS)

test-sm:
	$(CABAL_TEST) v2-test semantic-money --enable-tests \
		$(TEST_OPTIONS)

test-coverage:
	$(CABAL_COVERAGE) v2-build all --enable-tests --enable-coverage
	$(CABAL_COVERAGE) v2-test all --enable-tests --enable-coverage \
		$(TEST_OPTIONS)

.PHONY: test test-*

#
# Demos
#
demo-expo: build-test
	$(CABAL_TEST) v2-exec superfluid-validator -- --demo expo

demo-dfa: build-test
	$(CABAL_TEST) v2-exec superfluid-validator -- --demo dfa | ./utils/self-gnuplot.sh

demo-cfda: build-test
	$(CABAL_TEST) v2-exec superfluid-validator -- --demo cfda | ./utils/self-gnuplot.sh

.PHONY: demo-*

#
# Docs
#
docs-haddock:
	$(CABAL_DOCS) haddock all

YELLOWPAPER_ROOT = $(DOCS_BUILDDIR)/yellowpaper

$(YELLOWPAPER_ROOT)/tex:
	mkdir -p "$@"
$(YELLOWPAPER_ROOT)/tex/lhsfmt.tex:
	echo '%include lhs2TeX.fmt' | lhs2TeX > "$@"


.SECONDEXPANSION:
$(YELLOWPAPER_ROOT)/tex/%.lhs.tex: pkgs/core/src/Money/Theory/%.lhs
	./utils/lhs2tex.sh "$<" > "$@"

.SECONDEXPANSION:
$(YELLOWPAPER_ROOT)/tex/%.tex: yellowpaper/$$(notdir $$*).tex
	cp "$<" "$@"

.SECONDEXPANSION:
$(YELLOWPAPER_ROOT)/tex/%.bib: yellowpaper/$$(notdir $$*).bib
	cp "$<" "$@"

YELLOWPAPER1_FILENAME=semantic-money-yellowpaper1
YELLOWPAPER1_INPUTS = $(YELLOWPAPER_ROOT)/tex \
	$(YELLOWPAPER_ROOT)/tex/MoneyDistribution.lhs.tex \
	$(YELLOWPAPER_ROOT)/tex/FinancialContract.lhs.tex \
	$(YELLOWPAPER_ROOT)/tex/PaymentExecutionEnvironment.lhs.tex \
	$(YELLOWPAPER_ROOT)/tex/MoneyMedium.lhs.tex \
	$(YELLOWPAPER_ROOT)/tex/PaymentPrimitives.lhs.tex \
	$(YELLOWPAPER_ROOT)/tex/lhsfmt.tex \
	$(YELLOWPAPER_ROOT)/tex/preamble.tex \
	$(YELLOWPAPER_ROOT)/tex/Biblio.bib \
	$(YELLOWPAPER_ROOT)/tex/Paper1.tex
$(YELLOWPAPER_ROOT)/pdflatex/$(YELLOWPAPER1_FILENAME).pdf: $(YELLOWPAPER1_INPUTS)
	ls $(YELLOWPAPER_ROOT)/tex
	rm -rf $(YELLOWPAPER_ROOT)/pdflatex
	mkdir -p $(YELLOWPAPER_ROOT)/pdflatex
	rm -rf $(YELLOWPAPER_ROOT)/assets
	cp -r yellowpaper/assets $(YELLOWPAPER_ROOT)/assets
	cp $(YELLOWPAPER_ROOT)/tex/preamble.tex $(YELLOWPAPER_ROOT)/pdflatex/
	cd $(YELLOWPAPER_ROOT)/pdflatex; \
		P=$(YELLOWPAPER1_FILENAME); \
		{ \
			pdflatex -shell-escape -jobname=$$P ../tex/Paper1.tex && \
			biber $$P.bcf && \
			pdflatex -shell-escape -jobname=$$P ../tex/Paper1.tex; \
		}

docs-yellowpapers: $(YELLOWPAPER_ROOT)/pdflatex/$(YELLOWPAPER1_FILENAME).pdf

docs: docs-haddock docs-yellowpaper

.PHONY: docs-haddock docs

#
# Dev Environment
#
dev:
	nodemon \
		-e lhs,hs,cabal \
		-i dist-newstyle/ -i "$(TEST_BUILDDIR)/" -i "$(TEST_COVERAGE_BUILDDIR)/" \
		-i "#*" -i "flycheck_*.hs" \
		-x "make $(DEV_TARGETS) || exit 1"

freeze:
	rm -f cabal.project.freeze
	$(CABAL) v2-freeze

lint:
	for i in $$PWD/pkgs/*/*.cabal;do cd $$(dirname $$i);pwd;cabal -vnormal check || exit 1;done
	hlint pkgs


repl-sm:
	$(CABAL_TEST) repl semantic-money-test-suite

repl-simple:
	$(CABAL_TEST) repl superfluid-protocol-system-simple-test-suite

cloc:
	@echo '**** Core Source Files ****'
	cloc pkgs/core/src/
	@echo

	@echo '**** Simple System Source Files ****'
	cloc pkgs/simple/src/
	@echo

	@echo '**** Validator Source Files ****'
	cloc pkgs/validator/src/
	@echo

	@echo '**** Internal Source ****'
	cloc pkgs/src-internal/
	@echo

	@echo '**** Test Files ****'
	cloc pkgs/*/test
	@echo

.PHONY: dev freeze lint repl-* cloc
