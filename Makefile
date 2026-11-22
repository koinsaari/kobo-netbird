NETBIRD_VERSION := 0.83.1
TAR ?= tar

NETBIRD_ASSET := netbird_$(NETBIRD_VERSION)_linux_armv6.tar.gz
NETBIRD_URL := https://github.com/netbirdio/netbird/releases/download/v$(NETBIRD_VERSION)
B := build

.PHONY: all clean
all: $(B)/KoboRoot.tgz $(B)/kobo-netbird.zip $(B)/SHA256SUMS

clean:
	rm -rf $(B)

$(B)/$(NETBIRD_ASSET):
	mkdir -p $(B)
	curl -fsSL -o $@ $(NETBIRD_URL)/$(NETBIRD_ASSET)
	curl -fsSL $(NETBIRD_URL)/netbird_$(NETBIRD_VERSION)_checksums.txt | grep ' $(NETBIRD_ASSET)$$' | (cd $(B) && sha256sum -c -)

$(B)/cacert.pem:
	mkdir -p $(B)
	curl -fsSL -o $@ https://curl.se/ca/cacert.pem
	curl -fsSL https://curl.se/ca/cacert.pem.sha256 | (cd $(B) && sha256sum -c -)

$(B)/rootfs: $(B)/$(NETBIRD_ASSET) $(B)/cacert.pem $(shell find rootfs -type f)
	rm -rf $@ && cp -R rootfs $@
	mkdir -p $@/opt/netbird
	$(TAR) -xzf $(B)/$(NETBIRD_ASSET) -C $@/opt/netbird netbird
	install -D -m 0644 $(B)/cacert.pem $@/etc/ssl/certs/ca-certificates.crt
	touch $@

$(B)/KoboRoot.tgz: $(B)/rootfs
	$(TAR) --owner=0 --group=0 --numeric-owner --sort=name -czf $@ -C $< etc opt usr

$(B)/kobo-netbird.zip: $(B)/KoboRoot.tgz $(shell find drive -type f)
	rm -rf $(B)/drive && cp -R drive $(B)/drive
	mkdir -p $(B)/drive/.kobo && cp $< $(B)/drive/.kobo/
	cd $(B)/drive && rm -f ../kobo-netbird.zip && zip -qrX ../kobo-netbird.zip .kobo .adds

$(B)/SHA256SUMS: $(B)/KoboRoot.tgz $(B)/kobo-netbird.zip
	cd $(B) && sha256sum KoboRoot.tgz kobo-netbird.zip $(NETBIRD_ASSET) > SHA256SUMS
	cd $(B)/rootfs && find etc opt usr -type f | sort | xargs sha256sum | sed 's|  |  rootfs/|' >> ../SHA256SUMS
