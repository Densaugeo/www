#include config-test.env

PY=python3.12

RESET=\x1b[0m
BOLD=\x1b[1m
AQUA=\x1b[38;2;26;186;151m
BLUE=\x1b[38;2;68;170;221m
ORANGE=\x1b[38;2;236;182;74m

ifeq "$(shell id --name --groups $$USER | grep --count www)" "0"
ADD_GROUP_WWW=1
endif

install: caddy-installed.txt \
	selinux-configured.txt \
	/www \
	/www/systemd/www.service \
	notices
	@# Written for Fedora

caddy-installed.txt:
	# Need the COPR repo from Caddy because the version in the main Fedora
	# repo is too old - I use the log file mode option which was fixed in
	# version 2.9.0
	sudo dnf install -y dnf5-plugins
	sudo dnf copr enable -y @caddy/caddy
	sudo dnf install -y caddy
	sudo dnf info --installed caddy > caddy-installed.txt

selinux-configured.txt:
	sudo setsebool -P nis_enabled 1
	sudo setsebool -P httpd_use_fusefs 1
	@# Allows Caddy to access files labeled user_home_t. This is essential
	@# because this label is often applied to new files
	sudo setsebool -P httpd_read_user_content 1
	
	sudo semanage fcontext -a -t httpd_sys_content_t    "/www(/.*)?"
	sudo semanage fcontext -a -t httpd_config_t         "/www/caddy(/.*)?"
	@# SELinux offers a log type `httpd_log_t`, but it is useless because it
	@# does not allow writing to the logs
	sudo semanage fcontext -a -t httpd_sys_rw_content_t "/www/logs(/.*)?"
	sudo semanage fcontext -a -t systemd_unit_file_t    "/www/systemd(/.*)?"
	sudo semanage fcontext -a -t cert_t                 "/www/.*.pem"
	
	touch selinux-configured.txt

/www: caddy-installed.txt selinux-configured.txt
	@# Must be able to run caddy with no password for make dev
	@#echo "$$USER ALL = (caddy) NOPASSWD:$$(which caddy) run --envfile @config.env"\
	#	| sudo EDITOR=tee visudo -f /etc/sudoers.d/tir-na-nog

ifdef ADD_GROUP_WWW
	sudo useradd --system www
	sudo usermod --append --groups www $$USER
endif

	sudo mkdir -p /www
	sudo chmod 2775 /www
	sudo chgrp www /www
	
	@#mkdir -p files/restricted
	
	cd /www && mkdir caddy caddy/include logs root systemd
	chmod 775 /www/*
	sudo chown caddy /www/logs
	
	sudo restorecon -R /www

notices:
ifdef ADD_GROUP_WWW
	@printf '\n$(ORANGE)!!!! '
	@printf 'Current user added to $(BOLD)$(BLUE)www$(RESET)$(ORANGE) '
	@printf 'group. Relogin to update permissions, or run $(BOLD)$(AQUA)su '
	@printf '$$USER$(RESET)$(ORANGE) to update a single shell.'
	@printf ' !!!!$(RESET)\n\n'
endif

/www/systemd/www.service: /www /etc/systemd/system/www.service
	sudo ln -sf /etc/systemd/system/www.service $@

/etc/systemd/system/www.service: systemd/www.service \
	/www/caddy/Caddyfile-dev /www/caddy/Caddyfile-prod \
	/www/test-cert.pem
	sudo cp -f systemd/www.service $@
	sudo systemctl daemon-reload

/www/caddy/Caddyfile-dev: /www make-caddyfile.py
	ENVIRONMENT=dev python make-caddyfile.py > $@
	chmod 664 $@

/www/caddy/Caddyfile-prod: /www make-caddyfile.py
	ENVIRONMENT=prod python make-caddyfile.py > $@
	chmod 664 $@

/www/test-cert.pem: /www
	sudo openssl req -x509 -out $@ -keyout /www/test-key.pem \
		-newkey rsa:3072 -nodes -sha256 -subj "/CN=$$HOSTNAME" \
		-days 10000

	sudo chown caddy /www/*.pem

clean:
	for FILE in $$(ls systemd); do \
		systemctl list-unit-files $$FILE || continue; \
		sudo systemctl stop $$FILE; \
		sudo systemctl disable $$FILE; \
		sudo rm /etc/systemd/system/www.service; \
	done
	sudo rm -rf /www
