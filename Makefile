#include config-test.env

PY=python3.12

RESET=\x1b[0m
BOLD=\x1b[1m
AQUA=\x1b[38;2;26;186;151m
BLUE=\x1b[38;2;68;170;221m
ORANGE=\x1b[38;2;236;182;74m

ifneq "$(shell pwd -P)" "/www"
MOVE_REPO=1
endif

ifeq "$(shell id --name --groups $$USER | grep --count www)" "0"
ADD_GROUP_WWW=1
endif

install: test-cert.pem
	# Written for Fedora
	sudo dnf install -y caddy
	sudo setsebool -P nis_enabled 1
	sudo setsebool -P httpd_use_fusefs 1
	# Allows Caddy to access files labeled user_home_t. This is essential
	# because this label is often applied to new files
	sudo setsebool -P httpd_read_user_content 1
	
	# Must be able to run caddy with no password for make dev
	#echo "$$USER ALL = (caddy) NOPASSWD:$$(which caddy) run --envfile config.env"\
	#	| sudo EDITOR=tee visudo -f /etc/sudoers.d/tir-na-nog

ifdef ADD_GROUP_WWW
	sudo useradd --system www
	sudo usermod --append --groups www $$USER
endif

	sudo chown -R www:www .
	sudo find . -type d -exec chmod 775 {} \;
	sudo find . -type f -exec chmod 664 {} \;
	sudo chcon -R -u system_u -t httpd_sys_content_t .
	# Note: httpd_sys_rw_content_t is also available for content that Caddy
	# needs to be able to write
	#mkdir -p files/restricted
	
	sudo chcon -R -t httpd_config_t caddy
	
	sudo chown -R caddy:caddy logs
	# SELinux offers a log type `httpd_log_t`, but it is useless because it
	# does not allow writing to the logs
	sudo chcon -R -t httpd_sys_rw_content_t logs
	
	sudo chown caddy:caddy *.pem
	sudo chmod 644 *-cert.pem
	sudo chmod 600 *-key.pem
	sudo chcon -u system_u -t cert_t *.pem
	
	# SELinux restrictions on env files in SystemD are really, really stupid
	#sudo setenforce 0
	#sudo chcon -t unconfined_t /www/tir-na-nog/*.env
	#sudo setenforce 1
	
	sudo cp -f systemd/*.service /etc/systemd/system
	sudo systemctl daemon-reload

ifdef ADD_GROUP_WWW
	@printf '\n$(ORANGE)!!!! '
	@printf 'Current user added to $(BOLD)$(BLUE)www$(RESET)$(ORANGE) '
	@printf 'group. Relogin to update permissions, or run $(BOLD)$(AQUA)su '
	@printf '$$USER$(RESET)$(ORANGE) to update a single shell.'
	@printf ' !!!!$(RESET)\n\n'
endif

ifdef MOVE_REPO
	# Must be at end because make cannot create new shells after this
	cd .. && sudo mv www /www
	ln -s /www ..
	
	@printf '\n$(ORANGE)!!!! '
	@printf 'Repo moved to $(BOLD)$(BLUE)/www$(RESET)$(ORANGE) and a '
	@printf 'symlink left in its place. Run $(BOLD)$(AQUA)cd '
	@printf '../www$(RESET)$(ORANGE) to follow new link.'
	@printf ' !!!!$(RESET)\n\n'
endif

test-cert.pem:
	openssl req -x509 -out test-cert.pem -keyout test-key.pem \
		-newkey rsa:3072 -nodes -sha256 -subj "/CN=$$HOSTNAME" \
		-days 10000

	sudo chown caddy:caddy *.pem
	sudo chcon -u system_u -t cert_t *.pem
