TEST_OPTS ?= -vv
DEV_TARGET ?= build-src test-all
CERTORA_OPTS = \
	--packages @openzeppelin=../../node_modules/@openzeppelin @superfluid-finance/solidity-semantic-money/src=src \
	--optimistic_loop \
	--loop_iter 3 \
	--solc solc-0.8.23
FORGE_TEST = FOUNDRY_PROFILE=test forge test

# Other CERTORA_OPTS fragments:
	#--solc_args "['--via-ir', '--optimize']" \
	# --settings -t=2000 \

dev:
	nodemon -e sol -x sh -- -c "make $(DEV_TARGET) || exit 1"

build-src:
	forge build --sizes --skip 'test/**'

build-all:
	FOUNDRY_PROFILE=test forge build

clean:
	rm -rf out

test-all:
	$(FORGE_TEST) $(TEST_OPTS)

test-SemanticMoney:
	$(FORGE_TEST) --match-contract SemanticMoney $(TEST_OPTS)

test-ToySuperToken:
	$(FORGE_TEST) --match-contract ToySuperTokenTest $(TEST_OPTS)

test-Aqueduct:
	$(FORGE_TEST) --match-contract AqueductTest $(TEST_OPTS)

verify-ToySuperToken-invariances:
	certoraRun \
		test/ref-impl/CertoraHarness.sol:CertoraSuperfluidToken \
		test/ref-impl/CertoraHarness.sol:CertoraSuperfluidPool \
		--verify CertoraSuperfluidToken:certora/ToySuperToken.invariances.spec \
		$(CERTORA_OPTS) \
		$(CERTORA_EXTRA_OPTS)

verify-ToySuperToken-rules:
	certoraRun \
		test/ref-impl/CertoraHarness.sol:CertoraSuperfluidToken \
		--verify CertoraSuperfluidToken:certora/ToySuperToken.rules.spec \
		$(CERTORA_OPTS) \
		$(CERTORA_EXTRA_OPTS)

.PHONY: build-* clean dev test-* verify-*
