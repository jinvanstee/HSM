#!/bin/bash -ux

docker run -it -d --name=pkcs11-proxy-opencryptoki \
    -v /var/lib/opencryptoki:/var/lib/opencryptoki \
    -v /etc/opencryptoki:/etc/opencryptoki \
    --device=/dev/z90crypt:/dev/z90crypt \
    -e EP11_SLOT_NO=4 \
    -e EP11_SLOT_TOKEN_LABEL=EP11Tok \
    -e EP11_SLOT_SO_PIN=12345678 \
    -e EP11_SLOT_USER_PIN=84959689 \
    -p 2345:2345 \
    pkcs11-proxy-opencryptoki:s390x-1.0.0
