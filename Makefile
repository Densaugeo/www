#include config-test.env

PY=python3.12

RESET=\x1b[0m
BOLD=\x1b[1m
AQUA=\x1b[38;2;26;186;151m
BLUE=\x1b[38;2;68;170;221m
ORANGE=\x1b[38;2;236;182;74m

.PHONY: notices clean

ifeq "$(shell id --name --groups $$USER | grep --count www)" "0"
ADD_GROUP_WWW=1
endif

install: /www \
	/www/systemd/www.service \
	/www/caddy/Caddyfile-dev /www/caddy/Caddyfile-prod \
	/www/test-cert.pem \
	notices

/www:
	@# Written for Fedora
	@#sudo dnf install -y caddy
	@#sudo setsebool -P nis_enabled 1
	@#sudo setsebool -P httpd_use_fusefs 1
	@# Allows Caddy to access files labeled user_home_t. This is essential
	@# because this label is often applied to new files
	@#sudo setsebool -P httpd_read_user_content 1
	
	@# Must be able to run caddy with no password for make dev
	@#echo "$$USER ALL = (caddy) NOPASSWD:$$(which caddy) run --envfile @config.env"\
	#	| sudo EDITOR=tee visudo -f /etc/sudoers.d/tir-na-nog

ifdef ADD_GROUP_WWW
	sudo useradd --system www
	sudo usermod --append --groups www $$USER
endif

	sudo mkdir -p /www
	sudo chown www:www /www
	sudo chmod 775 /www
	sudo chcon -u system_u -t httpd_sys_content_t /www
	@# Note: httpd_sys_rw_content_t is also available for content that Caddy
	@# needs to be able to write
	@#mkdir -p files/restricted
	
	sudo mkdir -p /www/caddy
	sudo chown www:www /www/caddy
	sudo chmod 775 /www/caddy
	sudo chcon -u system_u -t httpd_config_t /www/caddy
	
	sudo mkdir -p /www/caddy/include
	sudo chown www:www /www/caddy/include
	sudo chmod 775 /www/caddy/include
	sudo chcon -u system_u -t httpd_config_t /www/caddy/include
	
	sudo mkdir -p /www/logs
	sudo chown caddy:caddy /www/logs
	@# SELinux offers a log type `httpd_log_t`, but it is useless because it
	@# does not allow writing to the logs
	sudo chcon -u system_u -t httpd_sys_rw_content_t /www/logs
	
	sudo mkdir -p /www/root
	sudo chown www:www /www/root
	sudo chmod 775 /www/root
	sudo chcon -u system_u -t httpd_sys_content_t /www/root
	
	sudo mkdir -p /www/systemd
	sudo chown www:www /www/systemd
	sudo chmod 775 /www/systemd
	sudo chcon -u system_u -t systemd_unit_file_t /www/systemd
	
	@# SELinux restrictions on env files in SystemD are really, really stupid
	@#sudo setenforce 0
	@#sudo chcon -t unconfined_t /www/tir-na-nog/*.env
	@#sudo setenforce 1
	
	@#sudo cp -f systemd/*.service /etc/systemd/system
	@#sudo systemctl daemon-reload

notices:
ifdef ADD_GROUP_WWW
	@printf '\n$(ORANGE)!!!! '
	@printf 'Current user added to $(BOLD)$(BLUE)www$(RESET)$(ORANGE) '
	@printf 'group. Relogin to update permissions, or run $(BOLD)$(AQUA)su '
	@printf '$$USER$(RESET)$(ORANGE) to update a single shell.'
	@printf ' !!!!$(RESET)\n\n'
endif

/www/caddy/Caddyfile-dev: /www make-caddyfile.py
	ENVIRONMENT=dev python make-caddyfile.py > $@
	
	sudo chown www:www $@
	sudo chmod 664 $@
	sudo chcon -u system_u -t httpd_config_t $@

/www/caddy/Caddyfile-prod: /www make-caddyfile.py
	ENVIRONMENT=prod python make-caddyfile.py > $@
	
	sudo chown www:www $@
	sudo chmod 664 $@
	sudo chcon -u system_u -t httpd_config_t $@

/etc/systemd/system/www.service: systemd/www.service
	sudo cp -f systemd/www.service $@
	sudo systemctl daemon-reload

/www/systemd/www.service: /etc/systemd/system/www.service /www
	sudo ln -sf /etc/systemd/system/www.service $@

/www/test-cert.pem: /www
	sudo openssl req -x509 -out $@ -keyout /www/test-key.pem \
		-newkey rsa:3072 -nodes -sha256 -subj "/CN=$$HOSTNAME" \
		-days 10000

	sudo chown caddy:caddy /www/*.pem
	sudo chcon -u system_u -t cert_t /www/*.pem

clean:
	sudo rm -rf /www
	sudo rm /etc/systemd/system/www.service
