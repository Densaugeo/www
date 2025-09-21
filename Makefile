include config-test.env

PY=python3.12

RESET=\x1b[0m
BOLD=\x1b[1m
AQUA=\x1b[38;2;26;186;151m
BLUE=\x1b[38;2;68;170;221m

install: test-cert.pem
	# Written for Fedora
	sudo dnf install -y caddy
	sudo setsebool -P nis_enabled 1
	sudo setsebool -P httpd_use_fusefs 1
	# Allows Caddy to access files labeled user_home_t. This is essential
	# because this label is often applied to new files
	sudo setsebool -P httpd_read_user_content 1
	
	# Must be able to run caddy with no password for make dev
	echo "$$USER ALL = (caddy) NOPASSWD:$$(which caddy) run --envfile config.env"\
		| sudo EDITOR=tee visudo -f /etc/sudoers.d/tir-na-nog
	
	sudo chcon -R -t httpd_sys_content_t .
	# Note: httpd_sys_rw_content_t is also available for content that Caddy
	# needs to be able to write
	mkdir -p files/restricted
	
	sudo semanage fcontext -a -t httpd_sys_content_t "/www/files(/.*)?"
	sudo restorecon -R files
	
	mkdir -p logs
	sudo chown -R caddy:caddy logs
	sudo chcon -R -t httpd_log_t logs
	sudo -u caddy touch logs/access-test.log logs/access-prod.log
	
	# SELinux restrictions on env files in SystemD are really, really stupid
	sudo setenforce 0
	sudo chcon -t unconfined_t /www/tir-na-nog/*.env
	sudo setenforce 1
	
	sudo cp -f systemd/*.service /etc/systemd/system
	sudo systemctl daemon-reload

ifneq "$(shell pwd -P)" "/www"
	cd .. && sudo mv www /www
	ln -s /www ..
	
	@printf '\n\033[38;2;0;255;255m!!!! '
	@printf 'Repo was moved to /www and a symlink left in its '
	@printf 'place. Run `cd ../www` to follow new link'
	@printf ' !!!!\033[0m\n\n'
endif

test-cert.pem:
	sudo -u caddy openssl req -x509 -out test-cert.pem -keyout test-key.pem \
		-newkey rsa:3072 -nodes -sha256 -subj "/CN=$$HOSTNAME" \
		-days 10000
