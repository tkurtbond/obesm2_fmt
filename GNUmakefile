# besm2_fmt -- Oberon-2 (voc) port of the Ada besm2_fmt.  See AGENTS.md
# and PLAN.md.
#
# voc writes each module's .c/.h/.sym/.o into the current directory, so
# every voc invocation runs inside $(OBJ); voc's symbol search path
# starts at ".", which is how later modules find earlier ones' .sym.
# Modules must be compiled in import order.
#
# Targets are the .o files, not the .sym files: voc leaves an unchanged
# .sym untouched (old mtime), so a .sym target would never look up to
# date.

SHELL = bash

VOC      ?= /usr/local/sw/versions/voc/git/bin/voc
# Size model: olibfyaml requires -OC, and models can't be mixed, so
# every module here -- ArgParser's and olibfyaml's included -- gets it.
VOCFLAGS := -OC

# voc reads LDLIBS from the environment when it links a main module.
export LDLIBS := $(shell pkg-config --libs libfyaml)

# ArgParser.Mod and Err.Mod are installed by the ArgParser repo into the
# first directory of OBERON_MODULES (colon-separated); olibfyaml's
# modules are used from its checkout.  Neither is copied here.
OBERON_MODULES ?= /usr/local/sw/versions/oberon/include
OLIBFYAML      ?= $(HOME)/Repos/Oberon/olibfyaml
vpath %.Mod rtl src test $(subst :, ,$(OBERON_MODULES)) $(OLIBFYAML)/src

OBJ   := obj
BUILD := build

PROGRAM := besm2_fmt
MAIN    := Besm2Fmt

# Library modules, in import order.  Args is rtl/Args.Mod, standing in
# for voc's Args, which exists only in the -O2 library (AGENTS.md).
SHAREDMODS := Args Err ArgParser FyThin Fyaml FyamlStreams
PROGMODS   := Besm2Str Besm2Config Besm2Out Besm2Layout Besm2Cli Besm2Entities Besm2Terse Besm2Grid Besm2Hmm Besm2RawMs
LIBMODS    := $(SHAREDMODS) $(PROGMODS)

# Test support modules, and test programs (test/<name>.Mod, main modules).
TESTSUPPORT := Check
TESTS       := TestStr TestLayout TestEntities

LIBOBJS  := $(LIBMODS:%=$(OBJ)/%.o)
SUPPOBJS := $(TESTSUPPORT:%=$(OBJ)/%.o)
TESTBINS := $(TESTS:%=$(OBJ)/%)

# Only building needs the shared modules, so clean doesn't check for them.
ifneq ($(if $(MAKECMDGOALS),$(filter-out clean,$(MAKECMDGOALS)),all),)
$(foreach m,ArgParser.Mod Err.Mod,$(if $(wildcard $(addsuffix /$(m),$(subst :, ,$(OBERON_MODULES)))),,$(error $(m) is not in OBERON_MODULES ($(OBERON_MODULES)); run make install in ~/Repos/Oberon/ArgParser)))
$(if $(wildcard $(OLIBFYAML)/src/Fyaml.Mod),,$(error olibfyaml not found in OLIBFYAML ($(OLIBFYAML))))
endif

.PHONY: all test golden clean

all: $(PROGRAM)

$(OBJ):
	mkdir -p $@

# Library and support modules: -s lets voc create or change the .sym.
$(OBJ)/%.o: %.Mod | $(OBJ)
	cd $(OBJ) && $(VOC) $(VOCFLAGS) -s $(abspath $<)

# Import dependencies: a module must be compiled after, and recompiled
# when, each module it imports.  Add a line here for every new import.
$(OBJ)/ArgParser.o: $(OBJ)/Args.o $(OBJ)/Err.o
$(OBJ)/Fyaml.o: $(OBJ)/FyThin.o
$(OBJ)/FyamlStreams.o: $(OBJ)/Fyaml.o $(OBJ)/FyThin.o
$(OBJ)/Besm2Config.o: $(OBJ)/Besm2Str.o
$(OBJ)/Besm2Out.o: $(OBJ)/Besm2Str.o
$(OBJ)/Besm2Layout.o: $(OBJ)/Besm2Config.o $(OBJ)/Besm2Out.o $(OBJ)/Besm2Str.o
$(OBJ)/Besm2Cli.o: $(OBJ)/ArgParser.o $(OBJ)/Besm2Config.o $(OBJ)/Besm2Str.o $(OBJ)/Err.o
$(OBJ)/Besm2Entities.o: $(OBJ)/Besm2Layout.o $(OBJ)/Besm2Str.o $(OBJ)/Fyaml.o
$(OBJ)/Besm2Terse.o: $(OBJ)/Besm2Config.o $(OBJ)/Besm2Entities.o $(OBJ)/Besm2Layout.o $(OBJ)/Besm2Out.o $(OBJ)/Besm2Str.o
$(OBJ)/Besm2Grid.o: $(OBJ)/Besm2Config.o $(OBJ)/Besm2Entities.o $(OBJ)/Besm2Layout.o $(OBJ)/Besm2Out.o $(OBJ)/Besm2Str.o
$(OBJ)/Besm2Hmm.o: $(OBJ)/Besm2Config.o $(OBJ)/Besm2Entities.o $(OBJ)/Besm2Layout.o $(OBJ)/Besm2Out.o $(OBJ)/Besm2Str.o
$(OBJ)/Besm2RawMs.o: $(OBJ)/Besm2Config.o $(OBJ)/Besm2Entities.o $(OBJ)/Besm2Layout.o $(OBJ)/Besm2Out.o $(OBJ)/Besm2Str.o
$(SUPPOBJS): $(LIBOBJS)

# The main module (-m); voc links the imported modules' .o files from
# $(OBJ) and $(LDLIBS).  Its executable is named after the module, so
# it is copied to the program's real name.
$(OBJ)/$(MAIN): src/$(MAIN).Mod $(LIBOBJS) | $(OBJ)
	cd $(OBJ) && $(VOC) $(VOCFLAGS) $(abspath $<) -m

$(PROGRAM): $(OBJ)/$(MAIN)
	cp $< $@

$(OBJ)/Test%: test/Test%.Mod $(LIBOBJS) $(SUPPOBJS) | $(OBJ)
	cd $(OBJ) && $(VOC) $(VOCFLAGS) $(abspath $<) -m

# Every unit test, run from $(OBJ) (where TestLayout writes its capture
# files), then the command-line checks of test/cli.sh, then the
# golden-output comparison of test/golden.sh; fail at the end if any
# failed.
test: $(PROGRAM) $(TESTBINS)
	@status=0; for t in $(TESTS); do \
	  echo "== $$t"; (cd $(OBJ) && ./$$t) || status=1; \
	done; \
	echo "== cli.sh"; test/cli.sh ./$(PROGRAM) || status=1; \
	echo "== golden.sh"; test/golden.sh check ./$(PROGRAM) || status=1; \
	exit $$status

# Rewrite test/golden/ from the reference programs: the Ada besm2_fmt
# and, for the cases where the port follows it instead, besm2-rst.  See
# test/golden.cases.  Needs neither this program nor its build.
ADA_BESM2_FMT    ?= $(HOME)/Repos/RPG/Tools/besm2_fmt/besm2_fmt
SCHEME_BESM2_RST ?= besm2-rst
golden:
	ADA_BESM2_FMT=$(ADA_BESM2_FMT) SCHEME_BESM2_RST=$(SCHEME_BESM2_RST) test/golden.sh generate

clean:
	rm -rf $(OBJ) $(PROGRAM)

print-%: ; @echo $* = $($*)
