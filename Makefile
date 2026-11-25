# Build and install wrapper around Cargo.
#   make && sudo make install                 PREFIX defaults to /usr/local
#   make install PREFIX=$HOME/.local          user install, no sudo
#   make uninstall PREFIX=...                 same PREFIX as the install

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share
CARGO ?= cargo
CARGO_FLAGS ?=
TARGET ?= $(or $(CARGO_TARGET_DIR),target)

APP_ID = com.github.Switchcraft
VERSION := $(shell sed -n 's/^version = "\(.*\)"/\1/p' Cargo.toml | head -1)
# Languages in LINGUAS that have a .po file
LANGS := $(filter $(shell sed 's/#.*//' po/LINGUAS),$(basename $(notdir $(wildcard po/*.po))))
MO = $(LANGS:%=$(TARGET)/share/locale/%/LC_MESSAGES/switchcraft.mo)
APPS = $(DESTDIR)$(DATADIR)/applications/$(APP_ID).desktop
META = $(DESTDIR)$(DATADIR)/metainfo/$(APP_ID).metainfo.xml
ICONS = $(DESTDIR)$(DATADIR)/icons/hicolor
SCHEMAS = $(DESTDIR)$(DATADIR)/glib-2.0/schemas

# The .mo files sit next to the binary's ../share/locale, so translations
# also work from the build tree. The schema is for running from it:
#   GSETTINGS_SCHEMA_DIR=target/schemas target/release/switchcraft
all: $(MO) $(TARGET)/schemas/gschemas.compiled
	$(CARGO) build --release --locked $(CARGO_FLAGS)

$(TARGET)/share/locale/%/LC_MESSAGES/switchcraft.mo: po/%.po
	mkdir -p $(@D) && msgfmt -o $@ $<

$(TARGET)/schemas/gschemas.compiled: data/$(APP_ID).gschema.xml
	mkdir -p $(@D) && glib-compile-schemas --targetdir=$(@D) data

check:
	$(CARGO) test --locked $(CARGO_FLAGS)

# Copies only, so `sudo make install` never runs cargo as root
install:
	install -Dm755 $(TARGET)/release/switchcraft $(DESTDIR)$(BINDIR)/switchcraft
	install -d $(dir $(APPS)) $(dir $(META))
	sed -e 's|@BINDIR@|$(BINDIR)|' -e 's|@VERSION@|$(VERSION)|' data/$(APP_ID).desktop.in > $(APPS)
	sed -e 's|@VERSION@|$(VERSION)|' data/$(APP_ID).metainfo.xml.in > $(META)
	chmod 644 $(APPS) $(META)
	install -Dm644 data/icons/$(APP_ID).svg $(ICONS)/scalable/apps/$(APP_ID).svg
	install -Dm644 data/icons/$(APP_ID).png $(ICONS)/512x512/apps/$(APP_ID).png
	install -Dm644 data/$(APP_ID).gschema.xml $(SCHEMAS)/$(APP_ID).gschema.xml
	for l in $(LANGS); do \
	  install -Dm644 $(TARGET)/share/locale/$$l/LC_MESSAGES/switchcraft.mo \
	    $(DESTDIR)$(DATADIR)/locale/$$l/LC_MESSAGES/switchcraft.mo; done
	[ -n "$(DESTDIR)" ] || glib-compile-schemas $(SCHEMAS)

# Without DESTDIR it also removes the autostart entry and stops the monitor
uninstall:
	rm -f $(DESTDIR)$(BINDIR)/switchcraft $(APPS) $(META) \
	  $(ICONS)/scalable/apps/$(APP_ID).svg $(ICONS)/512x512/apps/$(APP_ID).png \
	  $(SCHEMAS)/$(APP_ID).gschema.xml \
	  $(LANGS:%=$(DESTDIR)$(DATADIR)/locale/%/LC_MESSAGES/switchcraft.mo)
	if [ -z "$(DESTDIR)" ]; then \
	  glib-compile-schemas $(SCHEMAS); \
	  rm -f "$${XDG_CONFIG_HOME:-$$HOME/.config}/autostart/switchcraft-monitor.desktop"; \
	  pkill -u "$$(id -un)" -f '(^|/)switchcraft --background$$' || true; \
	fi

clean:
	$(CARGO) clean

.PHONY: all check install uninstall clean
