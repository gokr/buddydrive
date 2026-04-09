.PHONY: build clean install test package deb

build:
	nimble build -d:release

clean:
	rm -rf bin/*
	rm -f src/buddydrive.out
	rm -rf debian/buddydrive
	rm -f debian/files
	rm -f debian/*.debhelper*
	rm -f debian/debhelper-build-stamp
	rm -f debian/substvars

test:
	nimble c -r tests/harness/test_peer_discovery.nim

install: build
	install -Dm755 bin/buddydrive $(DESTDIR)/usr/bin/buddydrive
	install -Dm644 debian/buddydrive.service $(DESTDIR)/lib/systemd/system/buddydrive.service

deb: clean build
	dpkg-buildpackage -us -uc -b

package: deb
