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
PROGMODS   :=
LIBMODS    := $(SHAREDMODS) $(PROGMODS)

# Test support modules, and test programs (test/<name>.Mod, main modules).
TESTSUPPORT := Check
TESTS       :=

LIBOBJS  := $(LIBMODS:%=$(OBJ)/%.o)
SUPPOBJS := $(TESTSUPPORT:%=$(OBJ)/%.o)
TESTBINS := $(TESTS:%=$(OBJ)/%)

# Only building needs the shared modules, so clean doesn't check for them.
ifneq ($(if $(MAKECMDGOALS),$(filter-out clean,$(MAKECMDGOALS)),all),)
$(foreach m,ArgParser.Mod Err.Mod,$(if $(wildcard $(addsuffix /$(m),$(subst :, ,$(OBERON_MODULES)))),,$(error $(m) is not in OBERON_MODULES ($(OBERON_MODULES)); run make install in ~/Repos/Oberon/ArgParser)))
$(if $(wildcard $(OLIBFYAML)/src/Fyaml.Mod),,$(error olibfyaml not found in OLIBFYAML ($(OLIBFYAML))))
endif

.PHONY: all test clean

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

# Every unit test; fail at the end if any failed.
test: $(PROGRAM) $(TESTBINS)
	@status=0; for t in $(TESTS); do \
	  echo "== $$t"; $(OBJ)/$$t || status=1; \
	done; exit $$status

clean:
	rm -rf $(OBJ) $(PROGRAM)

print-%: ; @echo $* = $($*)
