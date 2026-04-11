.PHONY: build build-gui clean install test package deb

build:
	nimble build -d:release

build-gui:
	nimble gui_release

clean:
	rm -rf bin/*
	rm -f buddydrive-gui
	rm -f src/buddydrive.out
	rm -rf debian/buddydrive
	rm -f debian/files
	rm -f debian/*.debhelper*
	rm -f debian/debhelper-build-stamp
	rm -f debian/substvars

test:
	nimble c -r tests/harness/test_peer_discovery.nim

install: build build-gui
	install -Dm755 bin/buddydrive $(DESTDIR)/usr/bin/buddydrive
	install -Dm755 buddydrive-gui $(DESTDIR)/usr/bin/buddydrive-gui
	install -Dm644 debian/buddydrive.service $(DESTDIR)/lib/systemd/system/buddydrive.service
	install -Dm644 buddydrive.desktop $(DESTDIR)/usr/share/applications/buddydrive.desktop
	install -Dm644 icons/hicolor/48x48/apps/buddydrive.png $(DESTDIR)/usr/share/icons/hicolor/48x48/apps/buddydrive.png
	install -Dm644 icons/hicolor/128x128/apps/buddydrive.png $(DESTDIR)/usr/share/icons/hicolor/128x128/apps/buddydrive.png
	install -Dm644 icons/hicolor/256x256/apps/buddydrive.png $(DESTDIR)/usr/share/icons/hicolor/256x256/apps/buddydrive.png
	install -Dm644 icons/hicolor/512x512/apps/buddydrive.png $(DESTDIR)/usr/share/icons/hicolor/512x512/apps/buddydrive.png

deb: clean build build-gui
	dpkg-buildpackage -us -uc -b -d

package: deb
