#!/bin/bash

# https://gist.github.com/kyledrake/d7457a46a03d7408da31
# https://andrewlock.net/creating-and-trusting-a-self-signed-certificate-on-linux-for-use-in-kestrel-and-asp-net-core/
# https://www.humankode.com/asp-net-core/develop-locally-with-https-self-signed-certificates-and-asp-net-core
# https://blog.zencoffee.org/2013/04/creating-and-signing-an-ssl-cert-with-alternative-names/

CONFIG_DIR="$1"
PREFIX="$2"

DATE=`date -Idate`
CA_TTL_DAYS=1825  # 5yrs
CA_REGEN_THRESHOLD=180  # > CERT_TTL_DAYS to ensure the CA always lives longer than issued certs
CERT_TTL_DAYS=120  # certs should rotate every 90 days
CERT_REGEN_THRESHOLD=30
CA_SUBJ="/C=US/ST=Massachusetts/L=Boston/O=mikeandwan.us/OU=IT/CN=maw_container_ca"
CERT_SUBJ="/C=US/ST=Massachusetts/L=Boston/O=mikeandwan.us/OU=IT/CN="

CERT_ROOT="/maw-certs"

CA_DIR="${CERT_ROOT}/ca"
CA_KEY="${CA_DIR}/ca.key"
CA_KEY_PWD="${CA_KEY}.pwd"
CA_CRT="${CA_DIR}/ca.crt"
CA_CRT_PWD="${CA_CRT}.pwd"

PROJECTS=(
    "api"
    "auth"
    "files"
    "photos"
    "signing"
    "www"
)

will_expire_soon() {
    local cert="$1"
    local threshold="$2"
    local secs_in_day=86400
    local threshold_secs=$(expr $threshold \* $secs_in_day)

    if [ -e "${cert}" ]
    then
        echo `openssl x509 -in "${cert}" -checkend "${threshold_secs}" |grep -c "will expire"`
    else
        echo "1"
    fi
}

gen_pwd() {
    openssl rand -base64 32
}

gen_cert() {
    local config_dir="$1"
    local prefix="$2"
    local project="$3"
    local certdir="${CERT_ROOT}/${project}"
    local certkey="${certdir}/${project}_${DATE}.key"
    local certreq="${certdir}/${project}_${DATE}.csr"
    local certcrt="${certdir}/${project}_${DATE}.crt"
    local certpfx="${certdir}/${project}_${DATE}.pfx"
    local certkeypwd="${certkey}.pwd"
    local certpfxpwd="${certpfx}.pwd"
    local activecrt="${certdir}/${project}.crt" # used by this script
    local activepfx="${certdir}/${project}.pfx" # used by server
    local activekey="${certdir}/${project}.key"
    local activekeypwd="${activekey}.pwd"
    local activepfxpwd="${activepfx}.pwd"
    local dhparam="${certdir}/dhparam_${DATE}.pem"
    local activedhparam="${certdir}/dhparam.pem"

    if [ ! -d "${certdir}" ]
    then
        mkdir -p "${certdir}"
    fi

    if [ ! -z "${prefix}" ]
    then
        prefix="${prefix}."
    fi

    local cert_expiring=$(will_expire_soon "${activecrt}" "${CERT_REGEN_THRESHOLD}")

    if [ "${cert_expiring}" = "0" ]
    then
        echo ''
        echo "* cert for ${project} is not expiring soon, it will not be generated."
        echo ''
    else
        echo ''
        echo '*********************************************************'
        echo "* creating certificate for -[${project}]-"
        echo '*********************************************************'
        echo ''

        # create password for the keyfile
        PASSWORD=$(gen_pwd)
        echo "${PASSWORD}" > "${certkeypwd}"

        # create password for the cert
        PASSWORD=$(gen_pwd)
        echo "${PASSWORD}" > "${certpfxpwd}"

        PASSWORD=

        # Generate the domain key:
        openssl genrsa -passout "file:${certkeypwd}" -out "${certkey}" 2048

        # Generate the certificate signing request
        subj="${CERT_SUBJ}${prefix}${project}.mikeandwan.us"
        openssl req -sha256 -subj "${subj}" -new -nodes -config "${config_dir}/${project}.conf" -key "${certkey}" -passin "file:${certkeypwd}" -out "${certreq}"

        # Sign the request with your root key
        openssl x509 -sha256 -days "${CERT_TTL_DAYS}" -req -extfile "${config_dir}/${project}.ext" -in "${certreq}" -CA "${CA_CRT}" -CAkey "${CA_KEY}" -passin "file:${CA_KEY_PWD}" -CAcreateserial -out "${certcrt}"

        # Check your homework:
        openssl verify -CAfile "${CA_CRT}" "${certcrt}"

        # Make pfx for kestrel
        openssl pkcs12 -export -out "${certpfx}" -inkey "${certkey}" -in "${certcrt}" -passin "file:${certkeypwd}" -passout "file:${certpfxpwd}"

        # create dhparams file
        openssl dhparam -out "${dhparam}" 2048

        # create symlink to new cert to make it available to services
        if [ -e "${activepfx}" ]
        then
            rm "${activepfx}"
            rm "${activecrt}"
            rm "${activekey}"
            rm "${activekeypwd}"
            rm "${activepfxpwd}"
            rm "${activedhparam}"
        fi

        # we used to use symlinks here, but now we copy the file so that this works
        # regardless of mount points (so this image can work with podman volumes and local)
        # filesystems
        cp -f "${certkey}" "${activekey}"
        cp -f "${certkeypwd}" "${activekeypwd}"
        cp -f "${certcrt}" "${activecrt}"
        cp -f "${certpfx}" "${activepfx}"
        cp -f "${certpfxpwd}" "${activepfxpwd}"
        cp -f "${dhparam}" "${activedhparam}"
    fi
}

# *************************************
# ROOT CA
# *************************************
prepare_root_ca() {
    if [ ! -d "${CA_DIR}" ]; then
        mkdir -p "${CA_DIR}"
    fi

    CA_CERT_EXPIRING=$(will_expire_soon "${CA_CRT}" "${CA_REGEN_THRESHOLD}")

    if [ "${CA_CERT_EXPIRING}" = "0" ]
    then
        echo '* CA cert is not expiring soon, it will not be generated.'
        echo ''
    else
        CA_KEY_NEW="${CA_DIR}/ca_${DATE}.key"
        CA_KEY_PWD_NEW="${CA_KEY_NEW}.pwd"
        CA_CRT_NEW="${CA_DIR}/ca_${DATE}.crt"
        CA_CRT_PWD_NEW="${CA_CRT_NEW}.pwd"

        echo '*********************************************************'
        echo '* creating certificate authority'
        echo '* for dev - please make sure to run the following to trust the new CA cert:'
        echo '*'
        echo "* sudo cp ${CA_CRT_NEW} /usr/share/pki/ca-trust-source/anchors/"
        echo '* sudo update-ca-trust'
        echo '*'
        echo '*********************************************************'
        echo ''

        # create password for the keyfile
        PASSWORD=$(gen_pwd)
        echo "${PASSWORD}" > "${CA_KEY_PWD_NEW}"

        # create password for the cert
        PASSWORD=$(gen_pwd)
        echo "${PASSWORD}" > "${CA_CRT_PWD_NEW}"

        PASSWORD=

        # create CA key
        openssl genrsa -aes256 -passout "file:${CA_KEY_PWD_NEW}" -out "${CA_KEY_NEW}" 2048

        # create CA cert
        openssl req -new -x509 -days "${CA_TTL_DAYS}" -key "${CA_KEY_NEW}" -subj "${CA_SUBJ}" -passin "file:${CA_KEY_PWD_NEW}" -passout "file:${CA_CRT_PWD_NEW}" -sha256 -extensions v3_ca -out "${CA_CRT_NEW}"

        # update symlink to point at current
        if [ -e "${CA_CRT}" ]
        then
            rm "${CA_KEY}"
            rm "${CA_CRT}"
            rm "${CA_KEY_PWD}"
            rm "${CA_CRT_PWD}"
        fi

        cp -f "${CA_KEY_NEW}" "${CA_KEY}"
        cp -f "${CA_KEY_PWD_NEW}" "${CA_KEY_PWD}"
        cp -f "${CA_CRT_NEW}" "${CA_CRT}"
        cp -f "${CA_CRT_PWD_NEW}" "${CA_CRT_PWD}"
    fi
}

# *************************************
# PROJECT CERTS
# *************************************
generate_all_certificates() {
    local config_dir="$1"
    local prefix="$2"

    for I in "${PROJECTS[@]}"
    do
        gen_cert "${config_dir}" "${prefix}" "${I}"
    done
}

main() {
    local config_dir="$1"
    local prefix="$2"

    prepare_root_ca
    generate_all_certificates "${config_dir}" "${prefix}"
}

if [ -z "${CONFIG_DIR}" ]
then
    echo '*********************************************************'
    echo ' PLEASE SPECIFY THE CONFIG DIRECTORY (dev | local | prod)'
    echo '*********************************************************'

    exit 1
fi

if [ ! -d "${CONFIG_DIR}" ]
then
    echo '*********************************************************'
    echo " CONFIG DIRECTORY [${CONFIG_DIR}] DOES NOT EXIST!"
    echo '*********************************************************'

    exit 2
fi

main "${CONFIG_DIR}" "${PREFIX}"
