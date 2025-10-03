import os

global_options =  '''\
{{
	# Not necessary, I just don't like the admin API
	admin off

	http_port {HTTP_PORT}
	https_port {HTTPS_PORT}

	# Required to run caddy without root/wheel
	skip_install_trust

	# Required for Quest compatibility. If OCSP stapling is left on, serving
	# files to Quest may work for up to one week, but will then fail due to
	# expiration issues. The OCSP bug can be confirmed by leaving OCSP stapling
	# on, waiting 8 days, and then running
	# `curl -v --cert-status https://HOSTNAME/`, which will end with the error
	# `curl: (91) OCSP response has expired`.
	ocsp_stapling off
}}
'''

local_block = '''\
https://{HOSTNAME},
https://localhost {{
	tls /www/test-cert.pem /www/test-key.pem

	file_server browse {{
		root /www/root
	}}

	log {{
		output file /www/logs/access-{ENVIRONMENT}.log {{
			mode 0644
		}}
		format json
	}}

	import include/*
}}
'''

public_block = '''\
https://{FQDN} {{
    file_server browse {{
        root /www/root
    }}

    log {{
        output file /www/logs/access-{ENVIRONMENT}.log
        format json
    }}

    import include/*
}}
'''

KNOWN_HOSTS = {
    'morpheus': 'tir-na-nog.den-antares.com',
}

hostname = os.environ.get('HOSTNAME')
environment = os.environ.get('ENVIRONMENT').lower()
assert environment in ['dev', 'prod']

parameters = {
    'HOSTNAME': hostname,
    'ENVIRONMENT': environment,
    'HTTP_PORT': 80 if environment == 'prod' else 8080,
    'HTTPS_PORT': 443 if environment == 'prod' else 8443,
}

if environment == 'prod' and hostname in KNOWN_HOSTS:
    parameters['FQDN'] = KNOWN_HOSTS[hostname]

print(global_options.format(**parameters))
print(local_block.format(**parameters))
if 'FQDN' in parameters:
    print(public_block.format(**parameters))
