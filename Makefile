PREFIX ?= /usr
LIBDIR ?= $(PREFIX)/lib
LIBEXECDIR ?= /usr/libexec
NM_PLUGIN_DIR ?= $(LIBDIR)/NetworkManager

SERVICE_CFLAGS := -O2 -fPIC -Wall -Wextra $(shell pkg-config --cflags gio-2.0 glib-2.0 libnm 2>/dev/null)
SERVICE_CFLAGS += -DWPROXY_RUNNER_PATH='"$(LIBEXECDIR)/wproxy-xray-runner"'
SERVICE_LIBS := $(shell pkg-config --libs gio-2.0 glib-2.0 libnm 2>/dev/null)

CORE_CFLAGS := -O2 -fPIC -Wall -Wextra $(shell pkg-config --cflags gio-2.0 glib-2.0 gmodule-2.0 libnm 2>/dev/null)
CORE_CFLAGS += -DWPROXY_PLUGIN_DIR='"$(NM_PLUGIN_DIR)"'
CORE_LIBS := $(shell pkg-config --libs gio-2.0 glib-2.0 gmodule-2.0 libnm 2>/dev/null)

GTK3_CFLAGS := -O2 -fPIC -Wall -Wextra $(shell pkg-config --cflags gio-2.0 glib-2.0 gmodule-2.0 libnm gtk+-3.0 2>/dev/null)
GTK3_LIBS := $(shell pkg-config --libs gio-2.0 glib-2.0 gmodule-2.0 libnm gtk+-3.0 2>/dev/null)

GTK4_CFLAGS := -O2 -fPIC -Wall -Wextra $(shell pkg-config --cflags gio-2.0 glib-2.0 gmodule-2.0 libnm gtk4 2>/dev/null)
GTK4_LIBS := $(shell pkg-config --libs gio-2.0 glib-2.0 gmodule-2.0 libnm gtk4 2>/dev/null)

VALIDATOR_CFLAGS := -O2 -Wall -Wextra $(shell pkg-config --cflags libnm gmodule-2.0 glib-2.0 2>/dev/null)
VALIDATOR_LIBS := $(shell pkg-config --libs libnm gmodule-2.0 glib-2.0 2>/dev/null)

all: wproxy-service libnm-vpn-plugin-wproxy.so libnm-vpn-plugin-wproxy-editor.so libnm-gtk4-vpn-plugin-wproxy-editor.so wproxyctl validate-plugin

wproxy-service: service/nm-wproxy-service.c
	$(CC) $(SERVICE_CFLAGS) -o $@ $< $(SERVICE_LIBS)

libnm-vpn-plugin-wproxy.so: plugin/nm-wproxy-editor-plugin.c
	$(CC) $(CORE_CFLAGS) -shared -o $@ $< $(CORE_LIBS)

libnm-vpn-plugin-wproxy-editor.so: plugin/nm-wproxy-editor.c
	$(CC) $(GTK3_CFLAGS) -shared -o $@ $< $(GTK3_LIBS)

libnm-gtk4-vpn-plugin-wproxy-editor.so: plugin/nm-wproxy-editor.c
	$(CC) $(GTK4_CFLAGS) -shared -o $@ $< $(GTK4_LIBS)

wproxyctl: cli/wproxyctl.py cli/wproxy_engines.py
	cp $< $@
	chmod 755 $@

validate-plugin: plugin/validate-plugin.c
	$(CC) $(VALIDATOR_CFLAGS) -o $@ $< $(VALIDATOR_LIBS)

.PHONY: desktop desktop-check
desktop:
	cd desktop && npm ci --prefer-offline --no-audit --no-fund && npm run build
	cargo build --release --locked --manifest-path desktop/src-tauri/Cargo.toml
	python3 tests/check-tauri-production.py desktop/src-tauri/target/release/wproxy-desktop

desktop-check:
	cd desktop && npm run build
	cargo check --locked --manifest-path desktop/src-tauri/Cargo.toml

.PHONY: plasma-plugin
plasma-plugin:
	cmake -S plasma-nm -B build/plasma-nm -DCMAKE_INSTALL_PREFIX=$(PREFIX)
	cmake --build build/plasma-nm --parallel
	ctest --test-dir build/plasma-nm --output-on-failure

check-deps:
	@pkg-config --exists gio-2.0 glib-2.0 gmodule-2.0 libnm gtk+-3.0 gtk4 || { \
		echo "Missing build dependencies. Need libnm + GTK3 + GTK4 development files." >&2; exit 2; }

check-python:
	python3 -m py_compile cli/wproxyctl.py cli/wproxy_engines.py manager/wproxy-manager.py scripts/live-routing-smoke.py scripts/install-cores.py
	sh -n service/wproxy-xray-runner scripts/install.sh scripts/uninstall.sh scripts/diagnose.sh scripts/recover-vpn-settings.sh scripts/repair-gnome-vpn-editor.sh scripts/repair-runtime.sh

test-service-profile-lookup: tests/test-service-profile-lookup.c service/nm-wproxy-service.c
	$(CC) $(SERVICE_CFLAGS) -o $@ $< $(SERVICE_LIBS)
	./$@

test-service-lifecycle: tests/test-service-lifecycle.c service/nm-wproxy-service.c
	$(CC) $(SERVICE_CFLAGS) -o $@ $< $(SERVICE_LIBS)
	./$@

.PHONY: test
test: test-service-profile-lookup test-service-lifecycle desktop-check
	./test-service-profile-lookup
	./test-service-lifecycle
	python3 -m unittest discover -s tests -p 'test_*.py' -v
	bash -n scripts/apply-fix.sh tests/headless-smoke.sh
	sh -n service/wproxy-xray-runner
	node --input-type=module --check < gnome-extension/wproxy@wrench.local/extension.js
	node tests/test-kde-commands.mjs
	node tests/test-kde-dedupe.mjs
	python3 tests/check-release.py

clean:
	rm -f wproxy-service libnm-vpn-plugin-wproxy.so libnm-vpn-plugin-wproxy-editor.so libnm-gtk4-vpn-plugin-wproxy-editor.so wproxyctl validate-plugin test-service-profile-lookup test-service-lifecycle
	rm -rf cli/__pycache__ manager/__pycache__
	rm -rf desktop/dist desktop/src-tauri/target
